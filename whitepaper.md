# PulseStrategy

### An ecosystem of immutable vault tokens with a floor that only rises

**Whitepaper & User Guide** · PulseChain · pulsestrategy369.com · [@pulsestrategy](https://x.com/pulsestrategy)

---

## TL;DR

PulseStrategy is a family of six ownerless smart contracts. Each one holds a single yield-bearing asset in a vault and issues its own token against it.

The rule that defines the entire system:

> **The amount of backing behind each token can never go down.**

Not "shouldn't." Not "is unlikely to." *Cannot* — there is no function in any of these contracts that lowers it. Every mint adds proportionally more assets than tokens. Every redemption leaves value behind. Nobody can pause it, upgrade it, drain it, or change the rules, because no owner exists.

You are not asked to trust a team. You are asked to read a contract.

---

# PART I — WHITEPAPER

## 1. The problem

Crypto has no shortage of upside. What it lacks is a floor.

Almost every token can go to zero, because almost every token's value is a story about the future. When the story weakens, there's nothing underneath. The protocols that *did* promise floors mostly died the same way: they funded the promise with emissions, needed constant new deposits to honor it, and had an admin key that could — and eventually did — change the terms.

The mechanisms that failed weren't floors. They were narratives with a treasury attached.

## 2. The ethos

PulseStrategy was designed backwards from one question: **what can a holder be certain of?**

Not "what returns can we advertise" — what can be *proven*, by anyone, by reading code that can never change?

The answer turned out to be small but solid: a redemption right against a pool of real assets, where the assets-per-token ratio only ever ratchets upward. That's it. That's the whole promise. Everything else in this document is a consequence of it, or an honest admission of what it doesn't cover.

This forced three design decisions that most projects avoid:

**No admin.** No owner, no multisig, no pause switch, no upgrade path, no governance. Not because governance is bad, but because a floor that someone can move isn't a floor. The cost is real: bugs are permanent, parameters can never be tuned, and nobody can rescue anything. We accept that cost, because the alternative undermines the only thing being promised.

**No emissions, no reserved supply, no team allocation.** 100% of every vault token that will ever exist is minted by the public through one formula, at a price anyone can compute. There is no pre-mine to explain away and no inflation schedule to outrun.

**No hidden mechanics.** Every fee is disclosed in this document and visible on-chain. The one place value leaves the system — a 0.5% protocol fee — is stated plainly below rather than buried.

The result is a token that does not promise to make you rich. It promises that its floor rises, that the floor is real, and that nobody can take it away. In a market that mostly sells the opposite trade, that's the differentiator.

## 3. How a vault works

Every vault in the family is the same machine with a different asset inside. It has exactly two functions.

### Mint — the ceiling

Deposit the vault's asset, receive vault tokens priced at **backing + 4.5%**.

That 4.5% premium doesn't go to a founder. **4.0 points stay in the vault**, which means the vault gains proportionally more assets than the tokens it just issued — so *every mint raises the floor for everyone who already held*. The remaining 0.5 points are the protocol fee (§8).

Minting is capped: see §5.

### Hold — the ratchet

Nothing to do. Backing-per-token only rises. Three streams feed it:

1. **Mint premiums** — every new minter pays above backing, and the excess stays behind
2. **Redemption fees** — every exit leaves 0.5% for the people who stayed
3. **The underlying asset's own yield** — vPLS accrues PulseChain staking rewards; HTTs pull toward HEX parity as their stakes mature

Plus **donations**: anyone can send the vault asset directly to a vault contract at any time. It raises backing for all holders instantly, and it is not restricted by the mint quota.

### Redeem — the floor

Burn your vault tokens, receive your exact pro-rata share of the vault, minus a **0.5% fee that stays in the vault** for remaining holders.

Redemption is **never gated, never paused, never quota-limited, never delayed.** The mint side of the system breathes; the exit does not. A floor with conditions attached is not a floor.

**Last-redeemer waiver:** if you redeem 100% of the outstanding supply, the 0.5% fee is waived and you take the entire vault. No assets are ever stranded in a fully-redeemed vault.

## 4. The ratchet, precisely

The invariant, stated formally:

> For any operation of these contracts, `vaultBalance / totalSupply` after ≥ `vaultBalance / totalSupply` before.

Why it holds, case by case:

| Operation | Effect on vault | Effect on supply | Net |
|---|---|---|---|
| Mint | +4.0% more than pro-rata | +tokens | **Backing rises** |
| Redeem | −pro-rata, +0.5% retained | −tokens | **Backing rises** |
| Transfer | none | none | **Unchanged** |
| Donation | +assets | none | **Backing rises** |

There is no fifth case. No admin function, no rescue function, no fee-change function, no upgrade hook exists to create one.

**Worked example — the genesis mint.** Vault is empty. You deposit 104.5 units of the asset:

- You receive **100** vault tokens (104.5 ÷ 1.045)
- 0.5 units go to the protocol fee
- The vault holds **104.0**
- Backing per token = **1.04** — above 1.0 from the very first transaction

**Worked example — you profit from the next person.** Continuing above: a second minter deposits 104.5. Vault holds 208.0, supply is ~195.6, backing rises to ~1.0632. Your original 100 tokens now redeem for ~105.8 units gross (~105.3 after fee) — more than the 104.5 you put in. **Their premium became your gain.** Then when *you* exit, your 0.5% fee becomes the next holder's gain.

**Rate of growth.** If every epoch's mint quota fills completely, backing-per-token grows about **+0.36% per epoch ≈ +21% per year** from mint premiums alone — before redemption fees and before the underlying asset's own yield. That figure is a *ceiling*, not a forecast: it assumes perpetual saturated demand. Real growth comes in waves, with flat stretches. Every un-filled epoch is a week the ratchet only moves from fees and asset yield.

## 5. The epoch quota

Each **7-day epoch**, total minting is capped at **10% of the supply** that existed at the epoch's first mint. When the quota fills, `mint()` reverts until the next epoch opens.

The genesis epoch — while supply is zero — is **uncapped**, so the vault can bootstrap. This is the only window in a vault's life when entry can never be quota-blocked.

Why throttle at all?

- **Scarcity creates the event.** Exhausted quota means new demand must go to the DEX, where nothing caps the price. When the next epoch opens, arbitrageurs race to mint at backing+4.5% and sell into the elevated market — filling the vault. Weekly rhythm, permanently.
- **It's deterministic.** No oracle, no randomness, no admin switch. `block.timestamp / 7 days`. Anyone can predict it; nobody can manipulate it.
- **It's a percentage, not a fixed number.** The quota grows with the vault. Sustained demand makes each epoch's capacity larger — the throttle relaxes exactly as the system matures.
- **It suppresses runaway premiums.** Every epoch, fresh supply enters and pulls price back toward backing. This is deliberate: a token trading far above its floor has a distant floor, and the floor is the product. We chose holder protection over chart optics.

## 6. Arbitrage — the engine

**This is how the vault fills.** Understanding it is worth the two minutes.

Each vault contract is its own market maker, quoting two permanent prices:

```
CEILING  →  mint()    at  backing × 1.045   (infinite ask, quota-limited)
FLOOR    →  redeem()  at  backing × 0.995   (infinite bid, never limited)
```

Between them sits a **~5% band**. The market price does whatever it wants inside that band. But the moment it steps outside, a risk-free trade appears:

**Price above the ceiling** → mint from the contract, sell on the DEX, pocket the difference.
*Vault gains 4.0% of the mint. Backing rises. Supply rises, pushing price back down.*

**Price below the floor** → buy cheap on the DEX, redeem at the contract, pocket the difference.
*Vault keeps the 0.5% fee. Backing rises. Supply burns, pushing price back up.*

Notice what happens in **both** directions: **the vault gets fed and holders get richer.** Every time price leaves the band, someone profits by pushing it back — and pays the vault for the privilege.

This is the elegant part. Arbitrageurs aren't a threat to be defended against; they're unpaid employees. They need no incentive program, no emissions, no partnership — just a profitable trade. Their self-interest *is* the mechanism. The traders extracting value from the market are, structurally, transferring a slice of it to holders on every crossing.

And the ordinary buyer who never mints, never arbs, and just holds? **They're the beneficiary.** The mint race happening above their heads is what funds their rising floor.

### For arbitrageurs specifically

- Both legs are permissionless and atomic-friendly. No allowlist, no delay, no KYC.
- `previewMint()` and `previewRedeem()` are view functions — simulate before you commit.
- Both `mint()` and `redeem()` take a slippage parameter (`minTokensOut` / `minAssetOut`). Use it.
- The quota resets on a fixed 7-day boundary — `timeToNextEpoch()` tells you exactly when the ceiling reopens. Epoch open is the most contested moment in each vault's week.
- `mintQuotaRemaining()` tells you how much room is left before the ceiling closes.
- The HEX vaults have an unusually clean loop: **HTT ↔ HEX liquidity already exists**, so both arb legs complete through an established pool.

## 7. Liquidity providing

Providing liquidity to a PulseStrategy pool is structurally different from LPing a normal token pair, and it's worth being precise about why — and about what it doesn't fix.

**The normal LP problem:** impermanent loss comes from price *wandering*. In a standard pair, price can go anywhere — 10x up, 90% down — and the AMM mechanically sells you the winner and buys the loser the whole way. The further price travels from where you entered, the worse it gets. There is no natural stopping point.

**Why these pools are different:** the vault contract enforces boundaries the market cannot cross for long.

- Price can't sustainably fall below the floor — arbitrageurs will buy your cheap inventory out of the pool and redeem it against the vault
- Price can't sustainably run above the ceiling — arbitrageurs mint fresh supply and sell it into your pool

So instead of a random walk across an unbounded range, you're LPing an asset that **mean-reverts inside a ~5% band around a ratchet that only moves one way.** Bounded divergence means bounded impermanent loss. And crucially, unlike a normal pair whose "fair value" can collapse, the band itself is anchored to a backing figure that structurally rises.

**The honest caveats:**

- **This reduces IL; it does not eliminate it.** Within the band, and during the moments before arbitrage closes a gap, you still take the standard LP tradeoff.
- **The floor is denominated in the vault asset, not dollars.** A PLSstr floor is measured in vPLS. If PLS collapses in USD terms, so does the USD value of everything — pool included. This system protects against *token-vs-asset* risk. It does nothing about *asset-vs-world* risk.
- **Thin pools are volatile pools.** Early on, depth is small and price swings hard inside the band.
- **Fees are the point.** Your compensation is the trading fees generated by all that arbitrage traffic — and this design *manufactures* arbitrage traffic on a weekly schedule.

The dashboard displays a **trailing realized fee APR** per pool once one exists: a backward-looking measurement of fees actually earned, not a projection, not a promise, and it excludes impermanent loss. We'd rather show you a real number that might be unimpressive than an advertised number that isn't real.

## 8. Fees, in full

There are exactly two, and one destination outside the vault.

| Fee | Amount | Where it goes |
|---|---|---|
| Mint premium | 4.5% over backing | **4.0% stays in the vault** (raises everyone's floor) |
| — protocol fee | 0.5% of that same 4.5% | Protocol fee address (below) |
| Redemption fee | 0.5% | **Stays in the vault** (raises everyone's floor) |

**There is no transfer tax.** Moving tokens between wallets, into a pool, or through a DEX costs nothing. The vault tokens are plain, fully-composable ERC20s.

**The protocol fee is carved out of the premium minters already pay — it is not added on top.** A minter pays 4.5% whether or not the fee exists; the fee only determines whether the last 0.5 points sit in the vault or fund the protocol. Because the vault still nets 4.0%, **every mint remains accretive**, and the core invariant is untouched.

It funds hosting, development, and future vaults. It is hardcoded, immutable, and publicly auditable — each vault exposes `totalProtocolFees` and emits a `ProtocolFeePaid` event on every mint. You can verify exactly what it has taken, forever.

**Protocol fee address:** `0x3E5a5764EBd24d8142638366d4c5674D86c2EC64`

## 9. The vault family

Six vaults. **One audited codebase** — the five HEXstr contracts are logically identical to each other, and share their core with PLSstr. Same economics everywhere: 4.5% mint / 0.5% redeem / 7-day epochs / 10% quota / no admin.

### PLSstr — PulseStrategy

| | |
|---|---|
| **Token** | PulseStrategy (`PLSstr`) |
| **Backing asset** | vPLS — Vouch liquid staked PLS |
| **Asset address** | `0x79BB3A0Ee435f957ce4f54eE8c3CFADc7278da0C` |
| **Decimals** | 18 |
| **Vault life** | Perpetual |

**Yield underneath:** vPLS is *value-accruing*. The vault's vPLS balance doesn't grow on its own — instead, **each vPLS becomes redeemable for more PLS over time** as Vouch's validators earn staking rewards. So PLSstr compounds on two independent layers: backing-per-token ratchets up in vPLS terms from premiums and fees, while every vPLS underneath grows in PLS terms. The second layer never has an "unfilled epoch" — it accrues through dead weeks, bear markets, everything.

### HEXstr-3000 → 7000 — HEXStrategy

Five dated vaults backed by **Actuator Finance HTTs** — liquid, tradeable claims on staked HEX, redeemable 1:1 for HEX at their redemption day.

| Vault | Asset | Asset address | Redemption day |
|---|---|---|---|
| `HEXstr-7000` | HTT-7000 | `0x47810bb3ECDc6b080CeB2d39E769F21Ff14AB7E9` | Jan 31, 2039 |
| `HEXstr-6000` | HTT-6000 | `0xcdBFaf528c7CeA55d0AEbdB93C218D6f23B24af3` | May 6, 2036 |
| `HEXstr-5000` | HTT-5000 | `0xE2D03779147A32064511dd2b9D37F66f3EeFAd7C` | Aug 10, 2033 |
| `HEXstr-4000` | HTT-4000 | `0x3Cf372aA6aAa46eDc4B8da86294deC0DDecED632` | Nov 14, 2030 |
| `HEXstr-3000` | HTT-3000 | `0xE9E1340A2b31d5D2a2dB28FB854a794E106b430a` | Feb 18, 2028 |

All HTTs are 8-decimal (HEX-denominated); the vault tokens mirror that automatically.

**Yield underneath:** an HTT trades at a discount to HEX before maturity, and that discount closes as its redemption day approaches — a scheduled pull toward par. So a HEXstr vault ratchets in HTT terms from premiums and fees, while each HTT underneath climbs toward 1 HEX. Together the maturities form a **HEX yield curve**: longer-dated vaults carry a bigger discount and a longer runway; shorter-dated ones converge sooner.

**⚠️ These are term vaults. Read this.** The vault contract holds and transfers HTTs — it cannot call Actuator's redemption itself. So when a redemption day arrives, the vault holds matured HTTs and **you must exit through two steps**:

1. **Redeem your HEXstr tokens at the vault** → you receive HTTs
2. **Redeem those HTTs at Actuator Finance** → you receive HEX

Do this **before and around the redemption day**, not years later. After maturity, HTT trading liquidity will thin out as everyone redeems, and Actuator's 1:1 guarantee applies within its redemption window. A HEXstr vault has a natural end of life; treat the redemption day as a real deadline on your calendar. The last-redeemer waiver means a full wind-down strands nothing in the vault.

## 10. What is guaranteed, and what is not

The credibility of everything above depends on being equally clear about both.

### Guaranteed by the contract

- **Backing-per-token never decreases** from any operation of these contracts
- **No owner, no admin, no upgrade path, no pause switch** — verifiable in the ABI
- **Redemption is always open** — no gate, no quota, no delay, no discretion
- **No transfer tax**, no reserved supply, no team allocation, no emissions
- **100% of supply is publicly minted** through one formula, forever
- **Every fee is on-chain and countable** (`totalProtocolFees`, events)

### Not guaranteed — read carefully

- **Market price.** Nothing forces the market to value a vault token above its floor. It can sit at the floor indefinitely. The floor rises; the price is the market's business.
- **The underlying asset's value.** Your floor is denominated in vPLS or HTT — *not* in dollars. If PLS or HEX falls in USD terms, so does your position. This system reduces the risk of the token relative to its asset. It does nothing about the asset itself.
- **The layers below.** PLSstr's entire backing is a claim on the **Vouch** liquid staking protocol. HEXstr's backing sits on a deeper tower: **HEX → Hedron/HSIs → Actuator Finance → this vault**. A failure, exploit, or depeg at any of those layers impairs backing even though this contract's math holds perfectly. Minters carry that risk in full.
- **PulseChain itself.** All six vaults live there and inherit its risks entirely.
- **Your entry cost.** A round trip costs ~5% (4.5% premium + 0.5% exit fee). You start below your own floor and need subsequent activity or asset yield to clear it. Early entrants benefit most from later activity; the last person to touch a vault eats their own premium.
- **Smart contract risk.** These contracts have not received a paid third-party audit. They are small, deliberately simple, publicly readable, and immutable — which means anyone can verify them, and *nobody can fix them.* A bug would be permanent. Read the code, or don't deposit.
- **Quota griefing.** Someone can mint an epoch's full quota and immediately redeem to block others, at a cost of ~5% of the quota value. It's expensive, self-limiting, and the cost lands in the vault — but it's possible.

**Nothing here is financial advice.** Verify every contract yourself before depositing.

## 11. Governance

There is none, and there never will be.

No token votes. No DAO. No parameter changes. No treasury to allocate. No roadmap that can alter the terms you agreed to when you minted.

The contracts are finished. That's not a stage of development — it's the product.

---

# PART II — USER GUIDE

## Quick start

1. Go to **pulsestrategy369.com** (or run your own copy — see below)
2. Tap **Connect** → Browser wallet or WalletConnect
3. Pick a vault from the switcher (PLSstr, or any HEXstr maturity)
4. Get the vault's asset — vPLS via [Vouch](https://vouch.run), HTTs via [Actuator Finance](https://actuator.finance) or a DEX
5. **Mint** with it, or just buy the vault token on the DEX and hold

## Reading the dashboard

| What you see | What it means |
|---|---|
| **Backing per token** | Assets in the vault ÷ tokens in existence. Your floor. It only goes up. |
| **The ratchet rail** | Visual of how far backing has climbed above 1.0. It only moves right. |
| **Vault holds** | Total assets in the vault right now |
| **Supply** | Total vault tokens in existence |
| **Mintable this epoch** | How much room is left before the ceiling closes this week |
| **Resets in** | Countdown to the next epoch — when the quota refills and the mint race restarts |

## How to mint

1. Select the vault, make sure you're on the **Mint** tab
2. Enter an amount (or hit **MAX**)
3. Check the preview: how many tokens you'll receive, and the 4.5% premium you're paying
4. Tap **Approve** — one transaction, lets the vault take your asset
5. Tap **Mint** — a second transaction

**What you're paying:** backing + 4.5%. You are immediately ~4.5% below your own redemption value, and that's not a trick — it's the toll that funds everyone else's floor, including yours when the next person mints. Mint if you believe activity will follow. Otherwise just buy on the DEX.

**If mint reverts with "quota exhausted":** that's the ceiling doing its job. Buy on the DEX, or wait for the epoch timer.

## How to redeem

1. **Redeem** tab
2. Enter an amount (or **MAX**)
3. Check the preview: assets out, and the 0.5% fee left behind
4. Tap **Redeem** — one transaction, no approval needed

You get your exact pro-rata share of the vault minus 0.5%. **This always works.** No quota, no pause, no delay — regardless of market conditions, epoch state, or anything else.

Redeeming 100% of the supply? The fee is waived and you take the whole vault.

## For HEXstr holders — the redemption day

Each HEXstr vault has a **hard date** (see §9). Around and before it:

1. **Redeem HEXstr at the vault** → receive HTTs
2. **Redeem HTTs at Actuator Finance** → receive HEX

Don't sleep past it. After maturity, HTT liquidity thins as everyone exits, and Actuator's 1:1 redemption operates within its own window. The vault will hold matured HTTs forever if you let it — it can't convert them for you.

## For liquidity providers

The pools section shows every known pool per vault, with live depth and a **trailing realized fee APR**.

Why LP here: arbitrage traffic is manufactured by the design — every band crossing routes through your pool. And your inventory risk is bounded, because price mean-reverts inside a ~5% band around a rising floor instead of wandering freely (§7).

Two practical notes: don't LP your entire position (LPing caps your upside on the LP'd portion when price runs), and remember the bounded-IL argument is about *token vs. asset* — it says nothing about the asset's own price.

## Run the frontend yourself

The entire app is **one self-contained HTML file**. Scroll to the footer and tap **⬇ Download this app**.

Open that file from your own device and it works completely — connect a wallet, read live data, mint, redeem. No server involved. It talks only to PulseChain's RPC nodes and your wallet.

**Why this matters:** if pulsestrategy369.com ever goes down, is censored, or has its DNS hijacked, your local copy still works and cannot be tampered with. The contract has no admin key; now the interface has no mandatory middleman. Verify your copy against the **SHA-256 hash** shown in the footer and cross-checked against the one published on [@pulsestrategy](https://x.com/pulsestrategy) — a compromised server can fake the page, but it can't fake a hash you got somewhere else.

## FAQ

**Can the team rug this?**
There is no mechanism to. No owner, no admin function, no upgrade path, no privileged supply. Read the verified source — that's the point. The one thing the founder gets is the same thing you get: tokens minted through the public formula, plus a disclosed 0.5% protocol fee, publicly counted on-chain.

**Why would backing ever go down?**
From these contracts, it can't. From the layers below — a Vouch failure, an Actuator failure, a HEX or PulseChain event — it can. That's the honest boundary of the guarantee.

**What if nobody uses it?**
Then backing grows only from asset yield, and the token trades at its floor. You'd hold roughly what you'd hold anyway, minus your entry cost. That's the downside case: dull, not catastrophic — which is the entire point of the design.

**Why is the mint premium so high?**
Because it's the ratchet. Every point of premium is a point that lands in the vault, permanently, for holders. It's a toll on entry that pays existing holders — and if you don't want to pay it, don't mint: buy on the DEX from an arbitrageur who did.

**Which vault should I use?**
PLSstr if you want PLS exposure with a perpetual vault and staking yield underneath. A HEXstr if you want HEX exposure with a scheduled pull-to-par — longer maturities carry a bigger discount and a longer life; shorter ones converge sooner but expire sooner. Match the maturity to your own horizon, and put the redemption day in your calendar.

**Is it audited?**
No paid third-party audit. The contracts are small, simple, immutable, and fully public. Verify them yourself, and size your position accordingly.

---

## Contracts

All on **PulseChain**. Verify every address on the block explorer before you interact with it — and never trust an address from a screenshot, a DM, or a link.

| Vault | Symbol | Backing asset |
|---|---|---|
| PulseStrategy | `PLSstr` | vPLS `0x79BB3A0Ee435f957ce4f54eE8c3CFADc7278da0C` |
| HEXStrategy-7000 | `HEXstr-7000` | HTT-7000 `0x47810bb3ECDc6b080CeB2d39E769F21Ff14AB7E9` |
| HEXStrategy-6000 | `HEXstr-6000` | HTT-6000 `0xcdBFaf528c7CeA55d0AEbdB93C218D6f23B24af3` |
| HEXStrategy-5000 | `HEXstr-5000` | HTT-5000 `0xE2D03779147A32064511dd2b9D37F66f3EeFAd7C` |
| HEXStrategy-4000 | `HEXstr-4000` | HTT-4000 `0x3Cf372aA6aAa46eDc4B8da86294deC0DDecED632` |
| HEXStrategy-3000 | `HEXstr-3000` | HTT-3000 `0xE9E1340A2b31d5D2a2dB28FB854a794E106b430a` |

**Protocol fee:** `0x3E5a5764EBd24d8142638366d4c5674D86c2EC64`

*Vault addresses are published at pulsestrategy369.com and on [@pulsestrategy](https://x.com/pulsestrategy) after deployment.*

---

*The vault has no owner. The floor only rises. Verify everything.*
