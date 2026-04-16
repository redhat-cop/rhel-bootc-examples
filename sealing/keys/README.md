This directory holds public key material committed to the repo.

`db.crt` is the Secure Boot db certificate (public). Generate it with:

```sh
just keygen
```

The corresponding private key (`db.key`) is never committed — it lives
in `target/keys/` locally and in the `SECUREBOOT_DB_KEY` CI secret.
