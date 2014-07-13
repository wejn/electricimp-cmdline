# Electric Imp code upload + code preprocessing utilities
There are two scripts in this package:

- `imp-nut-pp.rb`, a C-style preprocessor (very limited!)
- `imp-upload.rb`, code upload tool.

## `imp-nut-pp.rb`
This Ruby script is a very limited C-style preprocessor for `*.nut` files.

Basically it came from my need to re-use parts of codebase among different
projects (thus the `#include` support) plus I felt that having basic control
flow would be nice (`#ifdef`, etc).

### Installation
Install Ruby 2.0+, then place this script somewhere in your `$PATH`.

### Usage
Call it like:
```bash
imp-nut-pp.rb device.src.nut device.nut
```
which will pre-process `device.src.nut` into `device.nut`. If there's any
sort of error during preprocessing, you get Ruby stacktrace and the output
file is *not* touched. The output file is *atomically* rewritten if the
preprocessing finishes successfully.

Also note that you can omit output file, which will dump output to STDOUT.
And you can also omit input file, which will take input from STDIN.

Supported tags are:

- `#include "file"`, which includes given file (the file is also pre-processed)
- `#define VARIABLE [VALUE]`, which defines given variable
- `#undef VARIABLE`, which undefines given variable
- `#ifdef VARIABLE`, outputs iff `VARIABLE` is defined
- `#ifndef VARIABLE`, outputs iff `VARIABLE` is NOT defined
- `#else`, else block for preceding `#ifdef` or `#ifndef` block
- `#endif`, end of preceding `#ifdef`, `#ifndef`, `#else` block

In short, if you know C, you'll feel right at home. (I hope)

## `imp-upload.rb`
This Ruby script takes care of code upload from commandline to Electric Imp IDE.

It is in no way endorsed by Electric Imp, Inc. and in fact, *it uses
unofficial REST API that might change at any moment (thus breaking
this script)*.

It is based on a [forum post by mikob](http://forums.electricimp.com/discussion/2533/alternative-for-those-who-don039t-like-the-web-ide) but slightly
improved to suit my needs:

- it can auto-fetch the token in several ways
- it can login to the web api (and cache token)
- no need to enter any commandline options, all specified within config file

Bear in mind this was developed on Linux, in Ruby, and as a quickie. You might
need to get your hands dirty and know a bit of Ruby in order to get this
script to work.

### Installation
Install Ruby 2.0+, then install `json` and `sqlite3` gems.

To do the latter, run the following on a commandline:

```bash
gem install json sqlite3
```

Finally place this script somewhere in your `$PATH`.

### Usage
Create `config.json` file with (at minimum) two keys:
```json
{
	"model": 12345,
	"device": "1234567890123456"
}
```
Running `imp-upload.rb` will attempt to upload `device.nut`
and `agent.nut` (from current directory) to the EI cloud.

*Note*: failing to supply either of the files the code will be replaced
with empty string. That's the way the API works (no way around that).

By default (if no other keys are specified) the utility will
attempt to fetch your access token from your Firefox settings.
If that fails, you can use other options to adjust.

### Config file and options
There are two config files -- general one: `~/.electricimprc.json`,
and project-specific one: `./config.json`.

Syntax for both config files is the same -- JSON which has root object
an Object with keys.

Settings in project-specific config override general config. Thus
it makes sense to use general config for `email`+`password` (and
perhaps `no_token_autoextract`) and the project-specific config
for `model`, `device`, and other settings.

#### Model / device
Keys `model` and `device` are mandatory.

They determine where to upload your agent and device code.

You can copy&paste their value from Electric Imp IDE, just go to some
model (and device) and look at the url. It should look like this:

`https://ide.electricimp.com/ide/models/12345/devices/1234567890123456`

yielding model `12345` and device `1234567890123456`.

#### Token / authentication
By default the script first tries to extract your token from Firefox,
unless disabled by setting `no_token_autoextract` key to true.

If the default extraction fails (you don't have Firefox cookie strore
under `~/.mozilla/firefox/**/cookie.sqlite`) you can tweak the autodetect
in one of three ways (by setting appropriate config key):

- `token` specifies key straight in config file (not recommended)
- `ff_cookie_store` specifies alternate location of your `cookies.sqlite`
- `token_command` specifies shell command to run that will fetch the token (value will be passed to `IO.popen`)

Example commands:
```json
{
	"token_command": ["sqlite3", "cookies.sqlite",
		"SELECT value FROM moz_cookies WHERE baseDomain=\"electricimp.com\" and name=\"imp.token\""],
	"token_command": ["ssh", "-q", "user@remotehost",
		"sqlite3 ~/.mozilla/firefox/*/cookies.sqlite \"SELECT value FROM moz_cookies WHERE baseDomain=\\\"electricimp.com\\\" and name=\\\"imp.token\\\"\""],
}
```

In addition to extraction from firefox you can let the script login
to the IDE by specifying your `email` and `password`.

The script will login and then cache the token as `~/.electricimp-token`.
You can turn off the caching by setting `no_token_caching` key to true.

#### Code verification
By default the script tries to verify code before uploading.
You can turn that off by setting `no_verify` key to true.

## Other info
- Author: Michal "Wejn" Jirku (box at wejn dot org)
- License: CC BY 3.0
- Version: 0.1
- Created: around 2014-07-01
