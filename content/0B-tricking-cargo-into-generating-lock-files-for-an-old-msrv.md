+++
title = "Tricking cargo into generating lock files for an old MSRV (for fun?? and profit??)"
date = 2026-05-10
description = "im not going insane you are going insane"

[taxonomies] 
tags = ["rust"]
+++

So uh. For /*reasons*/ that I might expand on in future blog posts[^1] I needed to work on an old (~4y old) library... Without a commited lock file... With some dependencies being yanked... And some dependencies requiring much newer <abbr title="Minimal Supported Rust Version">MSRV</abbr>...

<!-- more -->

How it started:

1. `{library}` depends on `ahash ^0.7.6`[^2]
2. `ahash >= 0.6.0, <=0.7.6` is yanked
3. `ahash ^0.7.7` has <abbr title="Minimal Supported Rust Version">MSRV</abbr> `1.60.0`
4. `{library}` has <abbr title="Minimal Supported Rust Version">MSRV</abbr> `1.59.0`[^3]
5. uhhhhhhmmmmmmmmmm

So, I can't update `ahash` to a newer version, because it would not be supported by rust `1.59.0`. And I can't keep it at `0.7.6`, because the <abbr title="Minimal Supported Rust Version">MSRV</abbr> CI will not pass and thus I can't merge the PR... 

{% callout() %}

can't you just raise the <abbr title="Minimal Supported Rust Version">MSRV</abbr>?

{% end %}

I- look-

{% callout() %}

uhuh?

{% end %}

Yes, I /*could*/[^5] but a) I didn't think of that originally b) I never search for easy ways out c) it's nice to keep <abbr title="Minimal Supported Rust Version">MSRV</abbr> as is d) :(

Anyway-

What I'm looking for is a way to get a `Cargo.lock` file which would
- contain `ahash =0.7.6` (so that `cargo` actually allows me to get it), and
- only contain versions of libraries with <abbr title="Minimal Supported Rust Version">MSRV</abbr> <= `1.59.0`

-----

My first idea was to generate a lock file with a new version of `cargo`, and then manually downgrade `ahash` to `0.7.6`. At first I couldn't find how to downgrade things with `cargo` at all, but then a friend of mine, [Jonathan Brouwer](https://github.com/JonathanBrouwer)[^6], helped me find that the way to downgrade a dependency is `cargo update {dependency} --precise {version}`[^7].

However... That did not help much...

{{ 
  image(
      img="cargo update tonight? :eyes: cargo update tonight queen? cargo update tonight? :eyes:.png", 
      alt="Atuin command run history. Every of the 36 commands is in the form of `rustup run nightly cargo update --precise` and then a version and a name of a crate. Some crates like regex and serde_json are repeated multiple times.", 
      style="border-radius: 8px; width: 90%;"
      quality=100
  )
}}

(this is not even a half of ithn...)

There are two problems with this approach:

- There are /*so*/ many dependencies that need to be downgraded
- Some dependencies are interconnected and hard to downgrade
  - Crates with exact dependencies, like `serde x.y.z` depending on `serde_code =x.y.z` are /*especially*/ annoying
  - But even just "downgrading A requires downgrading B first because B depends on newer A than I want to downgrade to" can be tiring for popular crates

This is just completely impractical and I had to give up on this idea[^8].

-----

When my idea did not work, I went to the [rust community discord](https://discord.gg/rust-lang-community) and asked how I could generate the lock file. To my surprise I got a response the same day from [synapturanus zombie 𓆏 (frog)](https://konnorandrews.gitlab.io/descent-into-madness/), who recently helped someone else with a similar issue.

All that's needed to generate an <abbr title="Minimal Supported Rust Version">MSRV</abbr>-compatible `Cargo.lock` is

1. Make sure `package.rust-version` is set in the `Cargo.toml` to the <abbr title="Minimal Supported Rust Version">MSRV</abbr>
2. Remove existing `Cargo.lock` (if it exists)
3. `CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS="fallback" cargo +nightly check`
   - You can also set `resolver.incompatible-rust-version = "fallback"` in the cargo *config*, but that's mildly more annoying
4. profit!

***It's that shrimple folks!***

One caveat is that for this to work your dependencies need to set `rust-version` too. And since it only got introduced in Rust `1.56.0`, this might not work very well for `1.56.0` and a few succeeding versions. Still, you can use this method as a start, and then downgrade the dependencies that don't accurately set `rust-version`. As a data point, this method worked for me successfully on `1.65.0`, but not on `1.59.0`.

Moral of the story: commit your lock files. Also, asking for help leads to being helped. Crazy how that happens.

Thanks again to synapturanus zombie 𓆏 (frog) for helping with this; and thank you to Jonathan and Arya for reviewing this post <3

-----

okmeowbye :3

-----

[^1]: me when i lie
[^2]: see [The Cargo Book: Version requirement syntax](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html)
[^3]: yes, it's off by 1 version .-.
[^4]: (tbc i was doing a backport, so that is not bad in any way)
[^5]: and i actually ended up raising the <abbr title="Minimal Supported Rust Version">MSRV</abbr> in a case, before i found other ways to solve this
[^6]: nya :3
[^7]: {% callout() %} downgrading a dependency requires using `update` subcommand?.. {% end %}

      shush

      it makes sense, why would have a separate command for that?

      also how are you in the footnotes??

      {% callout() %} :) {% end %}
[^8]: turns out i make a pretty bad dependency resolver
