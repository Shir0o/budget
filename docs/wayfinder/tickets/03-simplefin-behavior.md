# SimpleFIN Bridge behavior

- **Status:** closed
- **Type:** `wayfinder:research`
- **Map:** [Budget business logic](../map.md)

## Question

How does SimpleFIN Bridge authenticate, what are its rate limits and date windows, and how does it represent pending transactions?

## Resolution

Source: simplefin.org protocol and Bridge developer guide.

- **Setup:**
  - The user pastes a **setup token** (base64 of a claim URL).
  - The app sends one `POST` to the claim URL and gets back an **access URL** that has HTTP basic-auth credentials embedded in it.
  - A setup token can be claimed only once. The access URL is the long-lived secret.
- **Fetch:** `GET {access}/accounts?start-date=<unix>&end-date=<unix>&pending=1`. Adding `account=<id>` fetches one account.
  - The response is `{errors: [...], accounts: [{org, id, name, currency, balance, available-balance, balance-date, transactions: [{id, posted, amount, description, payee?, memo?, transacted_at?, pending?}]}]}`.
  - `amount` and `balance` are decimal **strings**. Parse them to cents exactly; never go through floating point.
  - The `errors` array carries user-facing messages, such as "re-authenticate with your bank". Always show them.
- **Rate limit:** Bridge expects **≤ 24 requests per day** per access token. Repeatedly going over can get the token disabled. All-account and per-account requests are counted separately.
- **Date window:** keep each request to **≤ 90 days**. Deep history should come from bank or app exports, not from SimpleFIN.
- **Pending:** shows up only with `pending=1` and only if the bank supports it. A pending transaction has `pending: true` and `posted: 0`. **Banks may assign a new `id` when a pending transaction posts**, and the amount can change (tips, holds). Ticket 10 handles this.
- **Account names** come from the bank. They may include a masked number such as "Checking ...1234".
