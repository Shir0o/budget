# Schedule C business tags and deduction rules

- **Status:** closed
- **Type:** `wayfinder:research`
- **Map:** [Budget business logic](../map.md)

## Question

Which preset Business Tags should we ship, how does each map to an IRS Schedule C line, and what deduction rule does each one carry?

## Resolution

Source: IRS Instructions for Schedule C (Form 1040), Pub. 463 (travel, gifts, meals) and Pub. 535. **The app produces records, not tax advice.** Every report carries that disclaimer.

| Preset Business Tag | Schedule C line | Deduction rule |
|---|---|---|
| Self-employment income | Line 1 (gross receipts) | Income, 100% |
| Advertising | 8 | 100% |
| Car & truck (actual expenses) | 9 | 100% of the business-use % (set per tax year) |
| Contract labor | 11 | 100% |
| Insurance (business) | 15 | 100% |
| Legal & professional | 17 | 100% |
| Office expense | 18 | 100% |
| Rent / lease | 20b | 100% |
| Supplies | 22 | 100% |
| Taxes & licenses | 23 | 100% |
| Travel | 24a | 100% |
| Meals | 24b | **50%** |
| Utilities | 25 | 100% |
| Conferences & education | 27a (other) | 100% |
| Software & subscriptions | 27a (other) | 100% |
| Phone & internet | 27a (other) | **business-use %** (set per tax year) |
| Gifts | 27a (other) | **≤ $25 per recipient per tax year**. Each gift line needs a recipient |
| Bank & payment fees | 27a (other) | 100% |
| Other business expense | 27a (other) | 100% |

- **Rule kinds:** `full`, `percent(p)` (fixed, e.g. meals at 50%), `businessUse` (a % the user sets per tag per tax year), `perRecipientCap(amount)`.
- **Custom tags:** the user can add their own and pick a line and rule.
- **Not in v1:** a mileage log (standard mileage rate) and home office (Form 8829). They are not transaction-based, so they are out of scope.
