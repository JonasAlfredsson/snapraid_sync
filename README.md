# snapraid_sync

A script designed for automating the SnapRAID sync and scrubbing tasks, with
user configurable threshold values in order to prevent accidental syncs when too
many files have been changed/deleted. Use cron to trigger it on a schedule, and
have it notify you by email when syncs are successful or something has gone
wrong.

All output will be printed both to `stdout` and to a log file. This means that
it is possible to use this script interactively as well, which makes the task
of "forcing" a sync (when manual intervention is necessary) much easier.

This script is also used in my [Ansible "SnapRAID" role][1], which is why it
has been designed to be able to handle multiple SnapRAID arrays on the same
computer.


## Acknowledgments and Motive
This script is not an entirely original piece of work. I have had a lot of
inspiration from a couple of other similar scripts which exists out there:

- [ZackReed][2]
- [SidneyC][3]
- [mtompkins][4]
- [wdullaer][5]

However, none of these really fulfilled my desire to have a script that could be
configured through environment variables, in order to make it easy to use the
same script for multiple arrays and/or deploy via Ansible. So I took some time
to analyze the best parts and design choices from all of these sources, and then
build my own solution from that knowledge.



# Preparations

In order to use all of the features this script has to offer, some preparations
are necessary.


## Requirements
### SnapRAID
The most critical part of this script is of course that you have installed
[SnapRAID][6], and have created a [valid configuration file][7] for your array.
ZackReed has a good guide on how to [install SnapRAID][8] as well, in addition
to his version of this script mentioned [above](#acknowledgments-and-motive).

However, as mentioned in the introduction, for those who like Ansible it might
be interesting to check out my [Ansible "SnapRAID" role][1] as well.

### Mutt
If you want to be notified by email, when syncs are successful or something
goes wrong, you will need to install [`mutt`][9]. This is a very lightweight
email client that is able to authenticate with other IMAP services, which is
necessary if you want to send emails out to the world wide web, and it can be
installed with the following command:

```bash
sudo apt install mutt
```

Mutt then needs to be properly configured so it is able to send emails to you.
You will need an account on some other email service (Gmail/Hotmail) which can
be used to login to and send emails from. In the `examples/` folder there is an
example `muttrc` file which has been configured to use a Gmail account. You
will only need to change the `<user>` name/mail and `<supersectret>` password
to something that you control.

This `muttrc` config file need to be placed in the `$HOME` folder of the user
that will invoke the `snapraid_sync.sh` script. Since we usually want SnapRAID
to run as "root" (in order to be able to read all files), we should place the
file in one of these two places:

- `/root/.muttrc`
- `/root/.mutt/muttrc`

> Notice the leading dot on either the file or the folder.

When this is done you can type `sudo mutt` in the terminal to test to read/send
emails.


## Installation
To install this script you should move into a suitable directory of your choice
and clone this repository from GitHub:

```bash
git clone git@github.com:JonasAlfredsson/snapraid_sync.git
```

Inside the `src/` directory there will be four files that needs to be kept
together for this script to work as intended. The `snapraid_sync.sh` file is
the main executable for this project, and it will source the `utils_*` files
during runtime, so do not separate them.

It is important that the `snapraid_sync.sh` file is executable, which should
already be the case, but can also be achieved by the following command:

```bash
sudo chmod +x snapraid_sync.sh
```

After this, it should be possible to use this program by always providing the
full path to the `snapraid_sync.sh` file, but to be able to call the executable
from anywhere on your system you can also add its folder to your `$PATH`. This
can be done by including the following line at the bottom of your `~/.bashrc`
or `~/.zshrc` file:

```
PATH="${PATH}:/path/to/snapraid_sync/src"
```

By sourcing the edited file again, or just opening a new terminal, it should
now be possible to use `snapraid_sync.sh` without having to provide the full
path.



# Usage

There are two methods of usage which I have envisioned when I wrote this;
a daily non-interactive automatic sync/scrub via cron, and then an interactive
intervention when threshold values have been exceeded (i.e. force a sync).
I will begin by explaining the interactive intervention, since that one is
necessary if you have not yet made any syncs, and from that it should be easier
to understand how to properly set up cron with this.


## Interactive Intervention
If you only have a single SnapRAID array, and the config file is in the default
location (see the [defaults below](#environment-variables)), you should be able
to run a normal "sync" by just executing the following command:

```bash
sudo ./snapraid_sync.sh
```

> Notice the use of `sudo` in order to give SnapRAID root privileges (so it can
  read all files present on the filesystem).

### Force a "sync"
However, if this is the first time running a "sync", or you have deleted some
files, it will complain that the threshold values have been exceeded, and the
script will exit with an error and (if configured) notify by email. To override
this you will need to set the environment variable `FORCE_SYNC` to "true",
which can be achieved with either of these two options:

```bash
sudo ./snapraid_sync.sh force
```

```bash
sudo FORCE_SYNC="true" ./snapraid_sync.sh
```

The script will then not exit when threshold values are exceeded, but rather
stop and ask the user to confirm (with a `Y`) that a "sync" should be performed
irregardless of the "diff" status.

If this safety-prompt is annoying, or you are trying to automate everything, it
can be turned off by setting the environment variable `NONINTERACTIVE` to
"true". In combination with `FORCE_SYNC` this will make SnapRAID "sync"
irregardless of the threshold values, and these settings can be combined in
whichever of the following ways you are most comfortable with:

```bash
sudo ./snapraid_sync.sh force noninteractive
```

```bash
sudo FORCE_SYNC="true" NONINTERACTIVE="true" ./snapraid_sync.sh
```

or as a combination in some way:

```bash
sudo NONINTERACTIVE="true" ./snapraid_sync.sh force
```

> The trailing commands have precedence over the prepended environment
  variables.


## Non-Interactive Execution
[Above](#interactive-intervention) was a guide on how to do a "sync" manually,
but usually we want to have as much as possible automated. By creating an entry
in cron we can have this script be triggered automatically on a schedule we
choose, and have it keep the array in an up to date synced state without our
help.

When this script is run by cron you need to have the `NONINTERACTIVE` variable
set to "true", otherwise it might get stuck waiting for user input that will
never arrive. It is also recommended to set the user running this cron job to
"root", so that SnapRAID will be able to read all the files on the filesystem
without any issues.

An example cron configuration file can be found in the `examples/` folder, and
in that one it is easy to see how the user is set to "root" and the
`NONINTERACTIVE` variable is set to "true". Additionally a half-finished entry
of the email address is present, which should be changed to something that
you want.

It can also be seen that there are two entries present, with two different
schedules. The first one will trigger every day, except Monday, at 09:05 and
22:05 to run a "sync". The second one will only run on Mondays at 13:00, and
then it will also run a "scrub" in addition to the "sync" (see the trailing
"scrub" command). In both of these cases the output is routed to `/dev/null`,
since we collect all of it in the `LOG_FILE` instead.

The `crond` file needs to be renamed and placed under `/etc/cron.d/` to work. A
suggestion might be something like this:

```
/etc/cron.d/snapraid_sync
```

> Files inside this folder may not have any extensions, e.g. `*.sh`, or contain
  any [weird characters][11].

Something to remember is that cron does not read your user's `.bashrc` file (or
similar), which means that all the environment variables you want propagated
to the script needs to be defined in the cron job. For a complete list of all
available variables, look [below](#environment-variables).


## Environment Variables
These variables are read from the environment when this script is started, which
makes it easy to quickly point to another configuration file in case you have
multiple SnapRAID arrays on your system.

Here are the available variables, and their default values if nothing is
provided from the environment. If you are only using this script for a single
array/setup on a single computer, it is perfectly fine to go into this script
and manually change the defaults directly in the code. This way you will not
need to prepend any additional settings every time you run it.

### Important
- `EMAIL_ADDRESS`: The address which the notification emails should be sent to
                   (default: `""` [i.e. disabled])
- `DELETE_THRESHOLD`: Threshold value for deleted files, if exceeded no sync
                      will be made (default: `"0"`)
- `UPDATE_THRESHOLD`: Threshold value for updated files, if exceeded no sync
                      will be made (default: `"-1"` [`"-1"` for disable])
- `CONFIG_FILE`: The location of the SnapRAID array configuration file
                 (default: `"/etc/snapraid.conf"`)

### Optional
- `SCRUB_PERCENT`: The percentage of the array which should be scrubbed when
                   "scrub" is called (default: `"8"`)
- `SCRUB_AGE`: Only scrub files which are older than this amount of days
               (default: `"10"`)
- `EMAIL_SUBJECT_PREFIX`: A prefix which will be added to the subject line of
                          all notification mails
                          (default: `"SnapRAID on $(hostname) - "`)
- `MAIL_ATTACH_LOG`: Attach the entire log file to the notification mail
                     (default: `"false"`)

### Additional - Do not change these unless you know what you are doing.
- `FORCE_SYNC`: Run a "sync" even though threshold values have been exceeded
                (default: `"false"`)
- `NONINTERACTIVE`: Unless this is "true" the script will ask the user for
                    confirmation before forcing a sync (default: `"false"`)
- `RUN_SCRUB`: Run a "scrub" after the "sync" (default: `"false"`)
- `LOG_FILE`: The full path to the main log file (default: `""` [This will
              create a temporary file in `/tmp/`])
- `SNAPRAID_BIN`: The location of the SnapRAID executable binary
                  (default: `"/usr/local/bin/snapraid"`)
- `MAIL_BIN`: The location of the mail program's executable binary
              (default: `"/usr/bin/mutt"`)


## Log Rotation
During execution this script will produce output to four different files:

- `tmp_file`
- `mail_body`
- `tmp_mail`
- `LOG_FILE`

Those in lowercase letters will be created as temporary files in `/tmp/`, and
deleted after use, while the main `LOG_FILE` will remain after exit. This is
done so that you will be able to go back and look through the log to find
details about any errors which might have occurred.

However, by default this `LOG_FILE` is also created as a temporary file in
`/tmp/`, which means that sooner or later the system will remove it from that
folder. If you would like to keep it for longer you will need to define a
different path and manage housekeeping yourself.

A suggestion is to configure the `LOG_FILE` variable to point to a path like
this:

```
/var/log/snapraid_sync/sync.log
```

and then configure [`logrotate`][10] to make sure the logs are renamed and
compressed every day, and then have it delete the oldest ones so you do not
fill the folder with tons of files.

An example of a `logrotate` configuration file can be found inside the
`examples/` folder, and this file then needs to be renamed and placed inside
the `/etc/logrotate.d/` folder. A suggestion could be something like this:

```
/etc/logrotate.d/snapraid_sync
```

It is also possible to have this `LOG_FILE` attached to the notification email
that is sent. Just make sure that the variable `MAIL_ATTACH_LOG` is set to
"true" for the log to show up as an file attachment. However, a minor warning
regarding this is that the "diff" output will be present in this file, and if
you do not trust you email provider you might not want it to know about the
names of the files which you have on your computer. Therefore the default of
this setting is "false".






[1]: https://github.com/JonasAlfredsson/ansible-role-snapraid
[2]: https://zackreed.me/updated-snapraid-sync-script/
[3]: http://www.havetheknowhow.com/scripts/SnapRAIDSync.txt
[4]: https://gist.github.com/mtompkins/91cf0b8be36064c237da3f39ff5cc49d
[5]: https://gist.github.com/wdullaer/6e8f391e2f538b8e21a4
[6]: https://www.snapraid.it/
[7]: https://www.snapraid.it/manual#4
[8]: https://zackreed.me/setting-up-snapraid-on-ubuntu/
[9]: http://www.mutt.org/
[10]: https://linux.die.net/man/8/logrotate
[11]: https://unix.stackexchange.com/questions/458713/how-are-files-under-etc-cron-d-used#comment909641_458715
