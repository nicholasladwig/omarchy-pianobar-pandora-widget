# Self-contained Pandora player rebuild

## Goal

Replace the `pianobar` process with a player implemented by this plugin, so an
Omarchy install can clone and enable it without requiring a separately
installed Pandora client.

## Required Pandora access

An official implementation needs a Pandora Partner application before code can
authenticate or obtain playback sources. The application owner must provide:

1. A Pandora Partner Portal client ID.
2. A client secret handled outside the repository and outside QML source.
3. The allowed OAuth redirect or device authorization configuration.
4. Confirmation that the application is entitled to the desired playback
   sources for the account tier being supported.

Pandora's developer documentation describes the partner application,
OAuth authorization, and GraphQL authentication requirements:

- <https://developer.pandora.com/docs/getting-started/becoming-pandora-partner/>
- <https://developer.pandora.com/docs/key-concepts/applications/>
- <https://developer.pandora.com/docs/key-concepts/authorization-oauth2/>
- <https://developer.pandora.com/docs/reference/graphql-api/authentication-using-oauth2/>

Do not add an application secret to this repository, a plugin manifest, QML,
or a command line. It must be acquired during setup and stored through Secret
Service, with an OAuth flow that does not expose it to shell history or process
arguments.

## Implementation stages

1. **Partner setup** — obtain the application credentials and define the
   supported Pandora account and subscription cases.
2. **Authentication** — replace the current account form with an OAuth flow;
   store refresh credentials in Secret Service and keep only non-secret account
   metadata in the cache.
3. **Catalog and stations** — implement station listing, station selection,
   now-playing metadata, ratings, skip, tired, and queue from the approved
   Pandora API.
4. **Playback** — connect approved playback sources to an in-process supported
   audio backend, including pause, volume, seek/timing, and end-of-track
   transitions.
5. **Migration** — retain the present settings UI, move existing account data
   only with explicit user consent, and offer removal of the old pianobar
   configuration after the new player works.
6. **Marketplace review** — document all network endpoints and credential
   storage, add an updated screenshot, and submit the exact release commit for
   a new Marketplace security review.

## Current boundary

The existing release remains a `pianobar` widget. It must keep the three
manual packages (`pianobar`, `tmux`, and `libsecret`) installed. A bundled or
reverse-engineered client is not a safe substitute for approved Pandora API
access and playback rights.
