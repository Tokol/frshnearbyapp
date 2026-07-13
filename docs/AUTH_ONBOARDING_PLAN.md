# Authentication and onboarding plan

## Product decision

Use one welcoming entry screen for both sign-in and registration. Google, Apple,
Facebook, and email are sign-in methods—not account types. After authentication,
the backend checks whether a profile already exists:

- Existing profile: open the app immediately.
- New profile: continue into account-type onboarding.

Email opens a focused screen with **Create account** and **Sign in** modes. This
keeps email available without making the first screen feel like a long form.

## Onboarding flow

1. **Choose sign-in method** — social provider or email.
2. **Choose account roles** — Consumer can be selected alone or together with one
   seller role. Side-hustle producer and Registered business are mutually exclusive.
3. **Create profile** — private full name plus optional photo and phone. Sellers
   also choose a required public display name and can add an introduction.
4. **Business details** — shown only for Registered business.
5. **Review and consent** — clearly separate public profile data from private
   account and verification data.
6. **Confirmation** — consumers enter immediately; seller verification can remain
   pending without blocking access to the rest of the app.

## Account-type data

### Consumer

- Full name (private, required)
- Profile photo (optional)
- Phone number (optional)

### Side-hustle producer

- All consumer fields
- Display name (public, required)
- Short introduction (public, optional)
- Producer verification status

### Registered business

- All producer fields
- Business name (required)
- Farm name (optional; do not require both farm and business names)
- Business ID (required)
- VAT number (optional unless local tax rules require it)
- Business type
- Business address, city, and zip code (required)
- Business verification status

## UX and implementation notes

- Save onboarding progress after every step so users can safely leave and return.
- Keep authentication identity separate from profiles. One account can be a
  consumer plus either a side-hustle producer or registered business, and can gain
  roles later without creating another login.
- The public display name is distinct from the legal business name.
- Clearly label optional fields and mark required fields with `*`.
- Validate Business ID, VAT number, phone, and zip code by country on the backend.
- Keep the farm illustration visible above the sheet; it supplies atmosphere while
  the cards and icons carry the functional meaning.
- Social login callbacks and account lookup are integration points; the current UI
  is a navigable prototype and does not yet authenticate against a backend.
