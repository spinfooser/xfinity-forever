# Xfinity Forever

A simple shell script that can automatically authenticate to XFINITY networks using
the username and password supplied in the RADIUS config in Luci (OpenWRT ui).

# Requirements

This script is only tested for OpenWRT.

Two packages must be installed through opkg:

- curl
- wpad

# LAN DNS Configuration

Using Cloudflare or Google for DNS on the LAN interface is a must. Xfinity uses DNS requests
to track that multiple devices are using the same wifi connection. The hotspot will then
force you to reauthenticate, which causes network interruptions.

In the Luci UI, you can find this setting in `Interfaces -> LAN -> Use custom DNS servers`.
Enter your preferred provider DNS IP addresses there!

Suggestions: 1.1.1.1, 1.0.0.1, 8.8.8.8
