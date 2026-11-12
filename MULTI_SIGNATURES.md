# Multiple signatures and aliases

This local Geary fork adds:

- Any number of named signatures per account.
- A default signature that is used when an alias does not choose one.
- An alias-specific signature, selected independently of the default.
- An explicit **No signature** option for individual aliases.
- A signature chooser in the composer's **More options** menu.

## Configure

Open **Settings → Accounts**, select an account, then use the **Signature**
section:

1. Use **Add** to create a named signature.
2. Select a signature from the chooser to edit its body.
3. Enable **Use this signature by default** for the account-wide default.

To assign a signature to an alias, open **Settings → Accounts** and find the
address under **Email addresses**. The row itself has a **Signature** chooser
with:

- **Account default**
- **No signature**
- Every named signature in the account

Changing **From** in the composer now refreshes the signature even when both
addresses belong to the same account. Replies show a **Signature** row
directly below **From**, so the result is visible and can be corrected for
that one message. The composer's **More options** menu also lets you replace
the current signature manually.

## Storage

The fields are stored in the existing account configuration file:

- `signatures` contains the ordered signature names.
- `signature_html_N` contains each signature body.
- `default_signature` contains the account default's name.
- `alias_signatures` maps lowercase sender addresses to a signature name.

The original `signature` and `use_signature` fields remain in sync for
compatibility. A pre-existing single signature is migrated into the named
model the next time the account is saved.

## Build

```sh
meson setup build -Dprofile=development -Dvaladoc=disabled \
  -Dui_locale=ru_RU.UTF-8
meson compile -C build
meson devenv -C build geary
```

The development build can be installed alongside the distribution package:

```sh
meson configure build --prefix="$HOME/.local"
meson install -C build
```
