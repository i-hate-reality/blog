+++
title = "(null), data= [ 0x06 ]"
date = 2025-04-13
description = "debugging lsusb"

[taxonomies] 
tags = ["usb", "programming", "lowercase"]
+++

so, recently i've been "working" a lot with usb. both as-in trying to make a usb device and as-in trying to make an existing usb device work. (let's all pray that i'll write more about both of these projects later). and, well, this journey is one made of pain...

<!-- more -->

it's hard to pinpoint the exact problem, but for some reason the intersection of "usb", "linux permission management", "nixos", and some non-standard things is just so painful. the errors are entirely opaque, information online is sparse, problems are confusing, debugging tools non-existent or hard to find, \[...\].

today i successfully debugged one issue that turned out to be quite funny, let me share the story.

i'm mainly working with usb-hid devices (universal serial bus human interface devices devices), i.e. things like keyboards and mice -- peripherals. one thing that is very helpful when debugging issues with them is getting "hid-descriptor" -- description of the device and what it says it'll communicate.

on paper `lsusb` should be able to list this information, buuuut...
```shell
: ~; lsusb -d 1d50:615e -v | rg "HID Device Descriptor" -A9
Couldn't open device, some information will be missing
        HID Device Descriptor:
          bLength                 9
          bDescriptorType        33
          bcdHID               1.11
          bCountryCode            0 Not supported
          bNumDescriptors         1
          bDescriptorType        34 (null)
          wDescriptorLength     103
          Report Descriptors:
            ** UNAVAILABLE **
```

to be clear, report descriptors are the interesting part -- it describes what the peripheral reports to the host.

in this example it's quite easy to notice the error, but when i tried it for the first time it was a lot harder to notice because the error was between lines that my brain filtered out:
```shell
: ~; lsusb -d 1d50:615e -v

Bus 005 Device 013: ID 1d50:615e OpenMoko, Inc. Blank Slate
Couldn't open device, some information will be missing
Negotiated speed: Full Speed (12Mbps)
Device Descriptor:
  bLength                18
...
```
{% callout() %}

why is there a blank line at the start?..

{% end %}

idk.

but either way, if it can't open the device, trying to run it as root is usually a good idea:
```shell
: ~; sudo lsusb -d 1d50:615e -v | rg "Report Descriptors" -A1
          Report Descriptors:
            ** UNAVAILABLE **
```

that didn't help ;-;

and honestly, this is where my debugging stopped at first. i couldn't find anything explaining how to get report descriptors.

today i was trying to debug this issue *again* (i keep running into it!) and actually *was* able to find a [solution in the slashdev.ca blog](https://www.slashdev.ca/2010/05/08/get-usb-report-descriptor-with-linux/). i'm... not sure how i missed it the last time... whatever. i built a command based on the solution and...
```shell
: ~; echo -n "5-1.1.4:1.0" | sudo tee /sys/bus/usb/drivers/usbhid/unbind \
         && sudo lsusb -d 1d50:615e -v | rg "Report Descriptor" -A10 \
         && echo -n "5-1.1.4:1.0" | sudo tee /sys/bus/usb/drivers/usbhid/bind
5-1.1.4:1.0          Report Descriptor: (length is 103)
            Item(Global): Usage Page, data= [ 0x01 ] 1
                            (null)
            Item(Local ): (null), data= [ 0x06 ] 6
                            (null)
            Item(Main  ): (null), data= [ 0x01 ] 1
                            Application
            Item(Global): (null), data= [ 0x01 ] 1
            Item(Global): Usage Page, data= [ 0x07 ] 7
                            (null)
            Item(Local ): (null), data= [ 0xe0 ] 224
5-1.1.4:1.0⏎   
```

so, multiple things:
1. yaaay it works
2. unbinding and rebinding the device is annoying
3. why does it say `(null)` everywhere???

somehow `lsusb`'s parser must be broken ig?... but how and why... googling `lsusb descriptor "(null)"` of course yielded nothing.

one suspicion i had is that it might be a nixpkgs packaging mistake somehow. i looked at the source and sure enough they have a [suspicious patch](https://github.com/NixOS/nixpkgs/blob/82f9b33efe8953dcbd930ac88e27632ba073c92f/pkgs/by-name/us/usbutils/fix-paths.patch):

```patch
diff --git a/lsusb.py b/lsusb.py
index bbc4dbb..8af1b1f 100755
--- a/lsusb.py
+++ b/lsusb.py
@@ -27,8 +27,7 @@ showwakeup = False
 
 prefix = "/sys/bus/usb/devices/"
 usbids = [
-	"/usr/share/hwdata/usb.ids",
-	"/usr/share/usb.ids",
+	"@hwdata@/share/hwdata/usb.ids",
 ]
 cols = ("", "", "", "", "", "")
```
i tried checking if the right path is in the `lsusb` binary, but had no success.

{% callout() %}
as it turns out, `lsusb.py` is a completely separate program from `lsusb` (although maintained by the same folks). `lsusb.py` provides different info that is sometimes nice to know, although it's unclear why `lsusb` can't do the same or vice versa...
{% end %}

i then also tried this on my friend's laptop (where `lsusb` comes from arch packages) and it had a similar bug, which suggests that this *isn't* packaging mistake.

i decided to look into `lsusb` [sources](https://github.com/gregkh/usbutils/blob/ff432498eb7aeb4fe33a27ddc89a0a43d7fe6fe1/lsusb.c), hoping that maybe i can just see the bug. `^Fhid` found `dump_report_desc`, which calls `names_reporttag(btag)` (this is the function that returns `(null)`), which is just a wrapper over `names_genericstrtable` which is
```c
static const char *names_genericstrtable(const struct genericstrtable *t,
					 unsigned int idx)
{
	const struct genericstrtable *h;

	for (h = t; t->name; t++)
		if (h->num == idx)
			return h->name;
	return NULL;
}
```

{% callout() %}
wait...
{% end %}

yep. i immediately noticed something fishy -- the `for` loop assigns to `h`, but then uses `t` is the condition and post-iteration-thing, but then uses `h` in the body again.

it took me a bit of time to convince myself this is actually a bug, simply because i'm not very familiar with the c language. but sure enough this is a bug.

it's basically iterating over `t`, but then using `h` for return condition. this means that this function always returns `null`, unless it is asked to find the first element of the table. `git blame` shows that this was introduced when switching from hash tables to arrays+linear lookups.

do i even need to say that this would be easily caught by any reasonable language? oh well.

after that, i fixed the bug, created a [patched package](https://github.com/WaffleLapkin/nixos/commit/0cc4993866642dbf3388624e9e2a11ef7d0f056e) for my own usage and sent [a pr with the fix](https://github.com/gregkh/usbutils/pull/228) to the upstream.

okbye.

postscriptum: i only found this while writing this post, but it turns out `usbhid-dump` (still from the same package as `lsusb`) can dump the descriptor without unbinding the device?... (but it doesn't pretty print it) (why can't `lsusb` do the same?...)

```
: ~; sudo usbhid-dump -d 1d50:615e
005:013:000:DESCRIPTOR         1744574422.718624
 05 01 09 06 A1 01 85 01 05 07 19 E0 29 E7 15 00
 25 01 75 01 95 08 81 02 05 07 75 08 95 01 81 03
 05 07 15 00 25 01 19 00 29 67 75 01 95 68 81 02
 C0 05 0C 09 01 A1 01 85 02 05 0C 15 00 26 FF 0F
 19 00 2A FF 0F 75 10 95 06 81 00 C0 06 50 FF 0A
 56 4C A1 01 85 50 15 00 25 01 75 01 95 40 05 0A
 19 00 29 3F 81 02 C0
```
