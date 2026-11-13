# Cheaper-plan cancel warning

A climber who goes to cancel a plan that costs less than the standard yearly plan sees one "Heads up" first.
It says what they pay, how much cheaper that is than today's standard yearly price, and that they may not be able to get that rate again.
Then it gets out of the way: both buttons leave, and neither is a trap.

## Where it lives

Settings -> Manage Subscription is the only route to cancelling inside Ascend, and Apple's own sheet (`manageSubscriptionsSheet`) does the cancelling.
`AccountView` asks `CheaperPlanWarningViewModel` first; the system alert it draws is the whole surface.

| Piece | Owns |
|---|---|
| `CheaperPlanWarningPolicy` | The eligibility rule, a pure function of two values |
| `CheaperPlanWarning` | The copy and the button titles |
| `StoreKitSubscriberRateProvider` | Reading the held plan and the prices, live |
| `CheaperPlanWarningViewModel` | The read-ahead, the tap, the two buttons and the events |
| `CheaperPlanWarningAnalyticsEvent` | The three events |

## Who sees it

All of these, and nothing else:

- The climber's `app_access` entitlement is an auto-renewing App Store subscription that has not already been cancelled (`willAutoRenew`).
- Its yearly-equivalent price is lower than the yearly-equivalent price of the standard yearly product, in the same currency, and rounds to at least 1 percent cheaper.

A monthly plan is multiplied to a year before it is compared, so a monthly plan that costs more over a year than the yearly plan gets nothing.
Lifetime owners, a climber on the free week (it has no RevenueCat entitlement), a climber with no plan, a lapsed climber, one who has already cancelled, and anyone on the standard yearly price or above get nothing and go straight to Apple's sheet.

Nothing is hardcoded.
RevenueCat says which product holds `app_access`, whether it is a trial and whether it renews.
StoreKit prices it: the plan's `renewalPrice` is what its next renewal bills at, so a grandfathered subscriber whose product's list price moved still reads their own price, and a climber inside a trial reads what the trial will become.
The standard yearly price is the list price of `ASCEND_REVENUECAT_YEARLY_PRODUCT_ID` read from StoreKit now, so a price the captain changes in App Store Connect moves the warning with no release.
Currency strings come from the storefront (`SubscriptionRatePriceFormatter`).

## Copy

```
Heads up
You currently pay $9.99 per year. That's 67% cheaper than the current $29.99 per year. If you cancel, you may not be able to get that rate again.
[Keep my plan]  [Continue to cancel]
```

A climber still inside a free trial reads "Your rate is $9.99 per year." in place of "You currently pay $9.99 per year.", because they pay nothing yet.
A monthly plan reads "per month" against "per year" and compares on the yearly equivalent.
The percentage is a whole number.
Neither button carries a role, so the system does not bold one: they are equal.
There is no countdown, no guilt line and no extra confirmation.

## It never blocks cancelling

- The read happens when Settings opens, not when the row is tapped. A tap before the store has answered, a failed read, a switch that is off or a climber with no warning opens Apple's sheet at once.
- A later failed read keeps what the last good one said; it never newly warns and never delays.
- `Continue to cancel` opens the same sheet the row opened before this existed. `Keep my plan` dismisses and does nothing else.
- When Apple's sheet closes, the warning it was opened from is dropped and the plan is read again, so a climber who cancelled there and taps Manage Subscription again goes straight to Apple's sheet instead of being warned about a plan that no longer renews, even if that read fails.

This is also the App Review and consumer-protection posture: cancelling stays clear and reachable, and a one-tap informational step that leads straight on to it is not a barrier.

## Kill switch

`cheaper_plan_cancel_warning_enabled` (`RemoteFeatureFlag.cheaperPlanCancelWarning`), a Boolean that ships on.
Off, Manage Subscription opens Apple's sheet at once and the store is not read.
It is display only, so there is nothing to defer (`docs/remote-config-kill-switches.md`).

## Analytics

| Event | When | Properties |
|---|---|---|
| `cheaper_plan_warning_shown` | The alert reached the screen | see below |
| `cheaper_plan_warning_keep_tapped` | `Keep my plan` | see below |
| `cheaper_plan_warning_continue_tapped` | `Continue to cancel` | see below |

Every event carries `product_id`, `rate` and `standard_rate` (numbers, per billing period and per year), `currency`, `period` (`year`, `month`, `3 months`), `percent_cheaper` (whole number), `is_free_trial` and `surface` (`settings`).
A tap that never produced a warning sends nothing.

## Why the claim is "you may not be able to get that rate again"

**Not reliably, for the welcome rate.**
`ascend_yearly_welcome` ($9.99 a year) is sold only by the Superwall decline offer, and `docs/superwall-paywall-setup.md` says that offer is shown to everyone who closes the first paywall, a lapsed subscriber included.
So a climber who cancels, lets the plan end and reopens Ascend meets the gate, and closing the first paywall shows them the welcome offer at the same price again.
Apple's one-trial-per-subscription-group rule means they would not get a second free week, but the rate itself comes back.
Whether it does depends on the Superwall campaign's audience, which is a dashboard setting outside this repository.
Nothing in this repository configures an App Store win-back offer or an offer code that would re-grant it, and the free week grants access, not a price.

The captain's brief read "you won't be able to get that rate again", and the captain chose to soften it to "may not" rather than change the Superwall campaign's audience, so the sentence stays true for every plan it can name.
For a legacy or grandfathered price the stronger claim would hold, because nothing sells it any more, but the alert uses one sentence for every plan.
