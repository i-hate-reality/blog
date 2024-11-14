+++
title = "You wouldn't use `filter_map`, right?"
date = 2021-09-20
updated = 2021-09-21
description = "There is a function `Iterator::filter_map`. I want to argue that it's useless and Rust provides more powerful tools to replace it."

[taxonomies] 
tags = ["rust"]
+++

There is a function `Iterator::filter_map`. I want to argue that it's useless and Rust provides more powerful tools to replace it.

<!-- more -->

{% callout() %}
This ~~tweet~~ post is inspired by [this] tweet from Boxy. Thanks, Boxy. <3

[this]: https://twitter.com/EllenNyan0214/status/1425911176853139460?s=20
{% end %}

# What is `Iterator::filter_map`?

So [`filter_map`] is a function provided by the `Iterator` trait:

```rust
fn filter_map<B, F>(self, f: F) 
    -> FilterMap<Self, F>
    // -> impl Iterator<Item = B>
where
    F: FnMut(Self::Item) -> Option<B>,
```

It is similar to [`filter`] and [`map`] combined (hence the name), but also lets you take ownership of the item when removing (`filter`ing) it:

```rust
let mut filtered = Vec::new();
let unfiltered = iterator
    .filter_map(|x| match condition(&x) {
        true => Some(x),
        false => {
            // You couldn't do the same with just 
            // `filter` and `map` because `filter` 
            // only provides `&Item` while `map`
            // won't get the filtered elements.
            filtered.push(x);
            None
        }
    })
    .collect::<Vec<_>>();
```

{% callout() %}
This example could be better written using [`partition`] or [`partition_map`], like [this]. Still, you may need ownership to do something with the value you are filtering.

[`partition`]: https://doc.rust-lang.org/nightly/core/iter/trait.Iterator.html#method.partition
[`partition_map`]: https://docs.rs/itertools/0.10.1/itertools/trait.Itertools.html#method.partition_map
[this]: https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=c46656bf42e9f33c70cc53950518081b
{% end %}

So far, `filter_map` seems pretty useful, right? Well, turns out it's just a less general version of...

[`filter_map`]: https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.filter_map
[`filter`]: https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.filter
[`map`]: https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.map

# `flat_map` to rule them all

[`flat_map`] is another function provided by the `Iterator` trait. It looks like this: 

```rust
fn flat_map<U, F>(self, f: F)
     -> FlatMap<Self, U, F>
     // -> impl Iterator<Item = U::Item>
where
    F: FnMut(Self::Item) -> U,
    U: IntoIterator,
```

This function is equivalent to `map` combined with [`flatten`] (which, in turn, is equivalent to `flat_map(id)`, they are interchangeable). 

At first glance, it may seem like `filter_map` and `flat_map` are different: the first expects a function that returns `Option` while the other expects a function that returns something that can be turned into `Iterator`. But then, if you think about it, `Option` may be seen as a collection with 0 or 1 elements, and [`take`] is its [`next`] function (if you know how monads work, this might have been obvious). Moreover, `Option` actually [implements `IntoIterator`]! So... you can replace any call to `filter_map` with a call to `flat_map` and everything will continue to work just fine :flower:

We can't just remove `filter_map` because backwards compatibility sucks. But I don't think I'll use it ever again.

[`flat_map`]: https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.flat_map
[`flatten`]: https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.flatten
[`take`]: https://doc.rust-lang.org/std/option/enum.Option.html#method.take
[`next`]: +https://doc.rust-lang.org/std/iter/trait.Iterator.html#tymethod.next
[implements `IntoIterator`]: https://doc.rust-lang.org/std/option/enum.Option.html#impl-IntoIterator

# Some more takeovers from `Option: IntoIterator`

[`iter::once(x)`] is actually equivalent to `Some(x)` in cases where `IntoIterator` is expected. It is even [implemented using the option's `IntoIter`]. You probably shouldn't use `Some(x)` like this, but you could.

```rust
[1, 2, 3]
     .iter()
     .copied()
     // :thinking:
     .chain(Some(special))
     .chain(iter::once(special))
```

[`iter::once(x)`]: https://doc.rust-lang.org/std/iter/fn.once.html
[implemented using the option's `IntoIter`]: https://github.com/rust-lang/rust/blob/db1fb85cff63ad5fffe435e17128f99f9e1d970c/library/core/src/iter/sources/once.rs#L65

## `Result` is also `IntoIterator`

It behaves very like `Option`: If it's `Ok(_)` it'll yield exactly one item, otherwise, it won't yield anything. `Result::into_iter(res)` is the same as `Option::into_iter(res.ok())`. I haven't seen this impl used in practice. If you have an `impl Iterator<Item = Result<T, E>>` you can use `.flatten()` to ignore errors, I guess.

# Concerns

There are some concerns about whatever `flat_map` can replace `filter_map`. I don't think that they are significant, but they exist.

## Readability

The most important of the concerns: with `filter_map` intent may be clearer to some readers. I think that `flat_map` doesn't noticeably decrease readability, but that may be different to some other programmers, especially beginners.

## Optimizations

Since `filter_map` is more specialized and less complicated than `flat_map` it's possible that it can be better optimized. It's unclear how much does it affect speed or if it's possible to fix this with some specialization in standart library.

`filter_map` is also [32 bytes smaller] than `flat_map`.

[32 bytes smaller]: https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=72f01ae1b8877f501a37db2f33724fff

## Type inference

Since `filter_map` is less general, it can help type inference. For example ([playground]):

```rust
// Compiles
iter.filter_map(|_| <_>::default()).map(|x: T| {});

// Fails
iter.flat_map(|_| <_>::default()).map(|x: T| {});
```

However, in practice, it seems like `filter_map` is usually used with explicit `Option`, so this doesn't matter.

[playground]: https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=061a524a15d8d9c1d656aceb61949876

# Criticism

{% callout() %}
This article received some criticism that needed to be addressed. 

In response to it this paragraph was added in [2021-09-21 update].

[2021-09-21 update]: https://github.com/i-hate-reality/blog/pull/30
{% end %}

Turns out `filter_map` has one advantage over `flat_map` --- it can know its own size better. Since `filter_map` can't ever add more elements than there were previously, its [`size_hint`] is `(0, upper)` (where `upper` is the upper bound of the inner iterator). `flat_map`'s `size_hint` on the other hand returns `(0, None)` in most cases (it's a bit more complicated than that since `flat_map` stores iterators it can _sometimes_ know _a bit_ more).

It should be possible to specialize `flat_map` for `Option<_>` (and maybe `Result<_>`, etc) so it produces more accurate `size_hint`. However, at the moment of writing this there is no such specialization which may make `flat_map` considerably worse than `filter_map` in some scenarious. I'd like for `filter_map` to be fully equivalent to `flat_map`, however atm it simply isn't.

[`size_hint`]: https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.size_hint

# Conclusion

I still prefer to use `flat_map` over `filter_map`, it seems *right* (also for some reason I really like the name). When making your choice between the two consider readability and `size_hint` (see above). 

There are a lot of hidden things in Rust, which are hard to notice, but when you do notice them, you can only say "of course!" (for example `Option: IntoIterator`). I would recommend reading iterator docs carefully, there are a lot of hidden gems.

bye.
