# EzerPhone Privacy Policy

Last updated: 3 November 2026

EzerPhone is a SIP softphone. It connects only to the telephony servers that you
set up yourself, and the developer runs no server that the app talks to on its own.

## What the developer collects

Nothing. The app has no analytics, no advertising, no tracking and no crash
reporting, and it does not send any data to the developer.

## What stays on your iPhone

- **SIP accounts.** Server addresses, user names and settings are kept in the app's
  storage; passwords and tokens are kept in the iOS Keychain. They are sent only to
  the SIP server of that account, to sign in.
- **Contacts.** If you allow access, names and phone numbers are read from the iOS
  Contacts app and shown in EzerPhone so you can call them. They are not uploaded
  anywhere.
- **Call history and favourites** are kept in the app's storage on the device.
- **Microphone.** Audio is captured only during a call and is sent to the other
  party through your SIP server, as in any phone call.

## What goes to the servers you choose

- Calls and registration go to the SIP server of the account you set up. That
  server, and your telephony provider, see your account name, IP address, the
  numbers you call and the call audio. Their own privacy policies apply.
- If you turn on "knock" for an account, the app calls the HTTPS address you entered
  before signing in, so that server learns your current IP address.
- If you open a one-tap setup link (`ezerphone://setup?t=…`), its one-time code is
  sent to the setup service named in the app to fetch the account settings.

## Deleting your data

Deleting an account in Settings removes its settings and secrets from the device.
Deleting the app removes its storage; iOS may keep Keychain entries after that, so
delete the accounts in Settings first to remove their passwords as well.

## Children

EzerPhone is not directed at children and collects no data from anyone.

## Changes and contact

Changes to this policy are published in this file. Questions can be asked through
the issue tracker of the EzerPhone repository.
