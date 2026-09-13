+++
title = "Waffle Devlog 0"
date = 2023-04-02
description = "Things I've done this week (2023-03-27—2023-03-31)"

[taxonomies] 
tags = ["devlog"]
+++

Things I've done this week (2023-03-27—2023-03-31). This is mostly a log for *myself* so that I remember that I did things™ but you may be interested in reading it too, for whatever reason.

<!-- more -->

# Don't skip all directories when tidy-checking

While I've technically done this the week *before*, [the PR](https://github.com/rust-lang/rust/pull/109440) has been merged this week, so I'll document it here.

Context: in rustc development we have this thing called `tidy`. It is basically a custom linter to check some code style related things in the code base. The implementation is messy, but it works.

Well the gist of the problem fixed by my PR is that it stopped working. More precisely it stopped checking all files that live in directories (i.e. almost all files) because of a bug introduced by a PR that was meant to speed up it (well, I mean, doing nothing is pretty fast, so-). I've noticed this while trying to do another change in tidy and not being able to test my change.

Debugging the issue was a little big weird, because I assumed that the bug was in a specific check, rather than in the whole file-check-framework, but after a bit of `dbg!` debug printing I figured everything out. The fix itself wasn't hard — change a check that a file has an extension so that it doesn't ignore directories (that almost never have extensions).

However, after the fix was done & even reviewed, merging the PR proved to be hard. First of all we have (or had? I did not watch this closely) an issue that basically made it so merge fails 50% of the time, because of some weird issue in CI (see [this discussion](https://rust-lang.zulipchat.com/#narrow/stream/242791-t-infra/topic/Repeated.20failures.20related.20to.20LLVM.20tools.3F/near/344575051) and [this issue](https://github.com/rust-lang/rust/issues/108227) for details). Moreover it turns out that without the automatic `tidy` checks the code was not kept tidy, which meant that there was a high change that any merged PR made my PR unmergeable. But, eventually, it was merged so all is good :)

# Installing git on dev-desktop

While this isn't something that was done publicly, I still want to document this, since it was *wild*.

Context: I'm using a thing called [dev-desktop](https://forge.rust-lang.org/infra/docs/dev-desktop.html) — a service managed by the rust infra team, that allows rust contributors to use a cloud machine to contribute to rust. This mostly helps if you (like me) have slow/old/etc computer locally, which makes it harder to work with a big project like rust.

Context 2: on the dev-desktop machines the OS is ubuntu, which is annoying for many reasons, including outdated packages. One of the most annoying cases of outdated packages is `git` which, for example, doesn't have the setting to make `git push` automatically create remote branches ([`push.autoSetupRemote`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-pushautoSetupRemote)).

And so, I've seen that [`fee1-dead`](https://github.com/fee1-dead) solved this by installing git via nix (which you can do for your user without having root on the system, etc). This seemed easy at first, but later proved to be quite difficult due to computers being what they are.

First of all I `cargo install nix-user-chroot` and started following the [tutorial](https://nixos.wiki/wiki/Nix_Installation_Guide#nix-user-chroot).

The first problem turned out to be that I accidentally made it so that when I logging to shell, the chroot is entered multiple times, but since this is not allowed, the second attempt to enter chroot fails, crashing the shell. Now, this would be fine if I had an open `ssh` session and could fix that, but in the only open connection I did `. the_shell_config`, which abruptly ended my `ssh` session, locking myself out of `dev-desktop`. Moreover, it turns out that without working shell, it is impossibly to do anything through `ssh`:

- `ssh` runs your shell
- `ssh "/bin/bash"` and alike run the command in the shell via ``$SHELL -c command`
- `scp` also opens shell to run `sftp` server in it, so overwriting config with it is not an option (it just outputs `scp: Connection closed`)
- and so on — it is literally impossible to do anything, without another way to access the machine
- unless you have a known vulnerability with RCE, see this [question](https://serverfault.com/questions/94503/login-without-running-bash-profile-or-bashrc)

In the end I written to the `t-infra` channel on rust zulip, after which someone from the team commented out my problematic configs, fixing this problem.

The next problem was actually figuring out how to not run chroot multiple times, I ended up checking if `~/.nix-profile/bin/nix-env` exists.

The next problem was vscode's ssh feature not working. Turned out that since I've re-ran `fish -l` in the chroot, my shell config never ended, so ssh's command did not get executed (internally vscode does `ssh host command`). Eventually I figured that I can check for `status is-interactive` before entering chroot.

The last (phew) problem was that the newly installed git, did not *actually* work:
```
:~/rust-b (better_docs_for_e0223); git push --force-with-lease
sudo: /etc/sudo.conf is owned by uid 65534, should be 0
sudo: /usr/bin/sudo must be owned by uid 0 and have the setuid bit set
^C⏎                                                      
```
Turns out `dev-desktop` uses a custom git credentials helper, which uses `sudo` to switch to some special user and the `sudo` just straight up does not work inside chroot. This was one of the most annoying issues here, having many sub-issues (I don't even want to remember anything about the path that lead to the final solution...), annoying shell techicalities, etc, etc...

In the end, my workaround is to run a server outside of chroot, that runs the `dev-desktop` git credentials helper when `nc`-ed into. I don't like this solution, it seems very fragile and bad, but it works, so I'll allow it.

`~/.config/fish/conf.d/nix.fish`:
```fish
# This is needed for the nix *in* chroot to work properly
# (exports some variables and stuff)
# (this was "added by Nix installer")
if test -e ~/.nix-profile/etc/profile.d/nix.fish;
    . ~/.nix-profile/etc/profile.d/nix.fish;
end

# This is needed to enter chroot
if test -e ~/.cargo/bin/nix-user-chroot;
    # Only enter chroot once
    # (otherwise it crashes shell)
    and not test -e ~/.nix-profile/bin/nix-env;
    # Don't run chroot if this is a non-interactive shell
    # (otherwise `ssh host command` hangs)
    and status is-interactive;

   # Before entering chroot, start a server that allows to get credentials from outside of chroot
   ~/unchroot-server/target/debug/unchroot-server &

   # Run a new shell inside chroot
   ~/.cargo/bin/nix-user-chroot ~/.nix fish -l;
end
```
`~/.gitconfig` (the empty `helper =` is needed to disable the non-hacked one):
```
[credential]
	helper =
[credential]
	helper = "~/git-credential-nix-chroot-compat"
```
`~/git-credential-nix-chroot-compat`:
```
#!/bin/fish

# if inside the chroot ...
if test -e /home/gh-WaffleLapkin/.nix-profile/bin/nix-env;
    # try connecting to the outside-of-chroot-server
    echo -e $argv "\n" (string join "\n" (cat -)) | nc localhost 6666
else
    # otherwise just run the actual credential helper
    git-credential-dev-desktop $argv;
end
```
The server:
```rust
use std::{
    io::{self, BufRead, BufReader},
    net::{TcpListener, TcpStream},
    process::{Command, Stdio},
};

fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("0.0.0.0:6666")?;

    // accept connections and process them serially
    for stream in listener.incoming() {
        handle_client(stream?);
    }
    Ok(())
}

fn handle_client(stream: TcpStream) {
    stream
        .set_write_timeout(Some(std::time::Duration::from_secs(5)))
        .ok();

    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(1)))
        .ok();

    let Ok(stream_clone) = stream.try_clone() else { return };

    let mut streamr = BufReader::new(stream);
    let mut streamw = stream_clone;

    let mut buf = String::new();
    streamr.read_line(&mut buf).ok();

    let Ok(child) = Command::new("git-credential-dev-desktop").args(buf.split(' ')).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn() else { return; };
    let Some(mut stdin) = child.stdin else { return };
    let Some(mut stdout) = child.stdout else { return };

    std::thread::spawn(move || _ = io::copy(&mut streamr, &mut stdin));

    io::copy(&mut stdout, &mut streamw).ok();
}
```

# Reviews

Pull requests I've reviewed in this week:

- [teloxide/867](https://github.com/teloxide/teloxide/pull/867) — basic documentation change, no need to scare users about a problem that was fixed a while ago
- [rust/109347](https://github.com/rust-lang/rust/pull/109347) — `#[no_mangle]` adjacent fix
- [rust/109554](https://github.com/rust-lang/rust/pull/109554) — suggest `0..=255u8` instead of `0..256u8` (which overflows)
- [rust/109149](https://github.com/rust-lang/rust/pull/109149) — improved suggestions for wrong  usages of `write!`
- [rust/109779](https://github.com/rust-lang/rust/pull/109779) ­— dependency updates
- [rust/109762](https://github.com/rust-lang/rust/pull/109762) — add a usage of `IndexVec` (an internal wrapper around `Vec` that allows use of new-typed indices)

# Stream

I'm trying to stream coding regularly now! The [schedule](https://www.twitch.tv/wafflelapkin/schedule) so far is every Wednesday at 15:30 UTC for about 3 hours. Although I'm thinking of adjusting that...

This week I've been trying to work on rustc diagnostics.

My first pick was issue [#109425](https://github.com/rust-lang/rust/issues/109425) where a suggestion to remove function arguments leaves a trailing comma. This turned out to be tricky. It's difficult to produce a correct suggestion, while also keeping the style of trailing comma, mostly because we don't have access to the commas (the code representation at hand doesn't tell anything about commas). Also the way this diagnostic is made is ... complicated, which makes it even worse. In the end I figured a hack and made a PR: [#109782](https://github.com/rust-lang/rust/pull/109782). I don't like this solution, but it fixes the issue, I think. We'll see what reviewers tell me.

The second pick was [#109271](https://github.com/rust-lang/rust/issues/109271) which is arguable even worse... The gist of the issue is this:
```rust
// f takes ``&mut self` and passes it to the closure
self.f(|this| self.x());
//           /^^^^^^^^
// this is an error since `self` is borrowed uniqly by `f`
```
We'd like for `rustc` to suggest changing `self` to `this`, since this is a common-ish pattern.

The problem is that such diagnostic must live inside the borrow checker, and the borrow checker diagnostics are *very* hard to do. This is because borrowck operates on MIR from which you can't easily get what the user has written. On top of that I had to do some shenanigans I did not know how to do, on top of _that_ I was becoming more and more tired as the stream progressed. In the end I made _some_ progress, I think I'm half way through it, but ultimately had to end the stream without finishing the fix.

I'm not sure this was a good stream, struggling while being watched is not the best feeling, although I guess it can be education.

It's probably just that I don't have enough experience, and in time my streams will be better and better... But it's very hard to believe in myself sometimes.

# Summary

I've been struggling with productivity recently, this week was mostly uneventful and foggy. To be honest I'm in a quite depressing mood, thinking that I'm not doing enough/that I'm doing everything wrong/etc. Idk what to say, hopefully I'll get better :")

P.S. yes, forgot to publish at the end of the week, oops
P.P.S. if you've read all of this: sorry
