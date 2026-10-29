# Budget math: rollover, overspending, credit cards

- **Status:** closed
- **Type:** `wayfinder:grilling` (user delegated the decision)
- **Map:** [Budget business logic](../map.md)

## Question

What are the exact formulas for category balances, Ready to Assign, overspending, and Card Payment Categories, shown as worked examples?

## Resolution

### Definitions (all integer cents; months are calendar months)

- **Activity(c, m):** the sum of transaction lines in category c dated in month m, including pending ones.
- **Available(c, m) = Carry(c, m) + Assigned(c, m) + Activity(c, m)**
- **Carry(c, m):**
  - If Available(c, m−1) ≥ 0: Carry = Available(c, m−1). Money rolls over forever.
  - If Available(c, m−1) < 0: Carry = 0. The negative amount is handled as overspending (below).
- **Cash overspending(c, m):** the part of a negative Available caused by spending from budget (non-card) accounts. It is **subtracted from Ready to Assign in month m+1**.
- **Credit overspending(c, m):** the part of a negative Available caused by card spending that was not funded. It is **not** subtracted from Ready to Assign. It stays as unfunded card debt (the card's balance is larger than its Card Payment Category).
- **Ready to Assign (a single global number):** all income lines (lines categorized to Ready to Assign, in budget accounts) − all Assignments in every month, including future months − all cash overspending from months already closed − uncategorized outflows (ticket 09). It can go negative; the UI then shows "over-assigned" and automation stops assigning.
- **Future months:** you may assign ahead. Future assignments reduce Ready to Assign immediately.
- **Transactions that count:** every entered transaction counts on its date, including pending ones. Scheduled (not yet happened) transactions never count; they only drive targets and forecasts.

### Accounts

- **Budget accounts** (checking, savings, cash, credit card) affect the budget.
- **Tracking accounts** (401k, mortgage) count toward net worth only.
- A transfer between two budget accounts has no category.
- A transfer from a budget account to a tracking account needs a category, because money leaves the budget. The reverse direction needs Ready to Assign or a category.

### Card Payment Category

One per credit card account, created automatically. When a card transaction line in category c is spent with Available(c) ≥ that amount, the same amount moves from c into the card's Card Payment Category. Inflows and refunds move it back.

### Worked examples

1. **Rollover.** Groceries: October Available $40. November Assigned $300, Activity −$280. November Available = 40 + 300 − 280 = **$60**, and it carries into December.
2. **Cash overspending.** Dining: November Available $20, debit spend $50, so Available = **−$30**. December: Dining Carry = 0, and Ready to Assign drops by **$30** on Dec 1.
3. **Card spending, fully funded.** Groceries Available $100. Spend $60 on Visa. Groceries becomes $40, and Visa Payment goes **+$60**. Paying $60 from checking to Visa is a transfer that brings Visa Payment to **$0**.
4. **Credit overspending.** Groceries Available $100. Spend $150 on Visa. Visa Payment +$100, and Groceries = **−$50** (credit overspending). Next month Groceries Carry = 0, Ready to Assign is unchanged, and Visa shows **$50 of unfunded debt** until you assign $50 to Visa Payment.
5. **Card refund.** A $20 Groceries refund on Visa: Groceries +$20 and Visa Payment −$20.
6. **Existing card debt** (at account creation or import): Visa Payment starts at $0, and the whole balance shows as unfunded debt.
7. **Split.** A $120 Target purchase split into $80 Groceries and $40 Household applies each line's rules on its own (card moves happen per line).
8. **Archiving a category that has a balance:** you must first move its Available to another category or back to Ready to Assign. Archiving with a non-zero balance is blocked.
9. **Income.** A $3,000 paycheck categorized to Ready to Assign: Ready to Assign +$3,000. Income can never be categorized directly into a spending category; refunds can.
