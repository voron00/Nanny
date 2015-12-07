#!/usr/bin/perl

# VERSION 3.x changelog is on github page https://github.com/voron00/Nanny/commits/cod2_english

# VERSION 2.99 changelog
# beta 1 - the voting state is now read from the server on startup rather than assumed to be on - me
# beta 2 - added server crash detection - automatically !resets itself after a server crash now.
# beta 3 - fixed a divide by zero condition in !stats when the player has no registered kills
# beta 4 - added the !friendlyfire command
# beta 5 - added affiliate server announcements feature.
# beta 6 - added the !broadcast command
# beta 7 - added flood protection for spam protection.  (lol)
# beta 8 - added the !hostname command
# beta 9 - added the !teambalance command
# beta 10 - tweaked flood protection for autodefining non-existent words.
# beta 11 - fixed the !unban command so it works with or without a # sign on the unban number
# beta 12 - private chat (/tell) awareness
# beta 13 - added the !forgive command
# beta 14 - bugfix/work-around where 999 quick kick would kick everyone at the start of a level.
# beta 15 - added passive FTP support (PASV) (config file option: use_passive_ftp)
# beta 16 - big red button
# beta 17 - retired the !teamkill command, and merged it with !friendlyfire

# VERSION 2.98 changelog
# beta 1 - adding mysql logging for jahazz
# beta 2 - allowed numbers within words for !define - doug and 666
# beta 3 - added prediction for next level, the !nextmap command - jahazzz
# beta 4 - double stats for some reason - LazarusLong
# beta 5 - fixed a bug in map prediction when the list is empty - me
# beta 6 - added one more strip-color in matching_users for double-color coded players
# beta 7 - does an rcon status immediately after a level change - helps with early admin access.
# beta 8 - fixed a divide by zero problem with stats that was crashing nanny. - Google Muffin
# beta 9 - Added periodic mysql database connection repair if it loses the MySQL server. - me
# beta 10 - Fixed a bug in the FTP code that was causing it to die - me
# beta 11 - Added auth_override - a super-admin access that even allows disabled !commands - me
# beta 12 - Added support for detecting and banning name thieves - me
# beta 13 - Fixed a bug in First Blood caused by falling to your death. - me
# beta 14 - Changed gravity and speed to disclose what they are currently set to - me
# beta 15 - Separated !gravity from auth_fly.  It now uses auth_gravity.
# beta 16 - Fixed a bug in !unban command that would crash nanny due to database locking - me
# beta 17 - !teamkill on/off via (auth_teamkill) - EmoKid

# To Do List:
#  monthly log rotations
#  guess a favorite weapon? :)
#  Rewrite config parser?
#  ability to specify tempban time via config?

#  Command wish list:
#  !teambalance on/off ...done
#  !forcerespawn on/off ...done
#  !spectatefree on/off ...done
#  !rifles on/off/only ...done
#  !bolt on/off/only ...done
#  !mgs on/off/only ...done

# NOTE:  rcon names have full color codes, kill lines have full colors, chat lines do not.

# List of modules
use strict;                     # strict keeps us from making stupid typos
use warnings;                   # helps us find problems in code
use diagnostics;                # good for detailed explanations about any problems in code
use Rcon::KKrcon;               # The KKrcon module used to issue commands to the server
use DBI;                        # databases
use DBD::SQLite;                # also needed to support databases
use Geo::IP;                    # GeoIP is used for locating IP addresses
use Geo::Inverse;               # Used for calculating the distance from the server
use Time::Duration;             # expresses times in plain english
use Time::HiRes qw (usleep);    # high resolution interval timers
use Time::Piece;                # object oriented time objects
use Socket;                     # Used for asking activision for GUID numbers
use IO::Select;                 # Used by the udp routines for manual GUID lookup
use LWP::Simple;                # HTTP fetches, simple procedural interface to LWP
use Net::FTP;                   # FTP support for remote logfiles
use File::Basename;             # ftptail support
use File::Temp qw/ :POSIX /;    # ftptail support
use Carp;                       # ftptail support

# Connect to sqlite databases
my $guid_to_name_dbh = DBI->connect("dbi:SQLite:dbname=databases/guid_to_name.db", "", "");
my $ip_to_guid_dbh   = DBI->connect("dbi:SQLite:dbname=databases/ip_to_guid.db",   "", "");
my $ip_to_name_dbh   = DBI->connect("dbi:SQLite:dbname=databases/ip_to_name.db",   "", "");
my $seen_dbh         = DBI->connect("dbi:SQLite:dbname=databases/seen.db",         "", "");
my $stats_dbh        = DBI->connect("dbi:SQLite:dbname=databases/stats.db",        "", "");
my $bans_dbh         = DBI->connect("dbi:SQLite:dbname=databases/bans.db",         "", "");
my $definitions_dbh  = DBI->connect("dbi:SQLite:dbname=databases/definitions.db",  "", "");
my $names_dbh        = DBI->connect("dbi:SQLite:dbname=databases/names.db",        "", "");
my $ranks_dbh        = DBI->connect("dbi:SQLite:dbname=databases/ranks.db",        "", "");

# Global variable declarations
my $version                    = '3.4 EN r77';
my $modtime                    = scalar(localtime((stat($0))[9]));
my $rconstatus_interval        = 30;
my $namecheck_interval         = 40;
my $idlecheck_interval         = 45;
my $guid_sanity_check_interval = 597;
my $guid0_audit_interval       = 295;
my $vote_timelimit             = 60;
my %WARNS;
my %idle_warn_level;
my %name_warn_level;
my $last_namecheck;
my $config;
my $config_name = 'nanny.cfg';
my $line;
my $first_char;
my $slot;
my $ip;
my $guid;
my $name;
my $ping;
my $score;
my $lastmsg;
my $port;
my $qport;
my $rate;
my $weapon;
my $attacker_guid;
my $attacker_name;
my $attacker_slot;
my $attacker_team;
my $victim_guid;
my $victim_name;
my $victim_slot;
my $victim_team;
my $attacker_weapon;
my $damage;
my $damage_type;
my $damage_location;
my $message;
my $time;
my $timestring;
my $currenttime;
my $currentdate;
my %last_activity_by_slot;
my $last_idlecheck;
my $last_rconstatus;
my %name_by_slot;
my %voted_by_slot;
my %ip_by_slot;
my %guid_by_slot;
my %ping_by_slot;
my %spam_last_said;
my %spam_count;
my $sth;
my $guid_to_name_sth;
my $ip_to_name_sth;
my $ip_to_guid_sth;
my $definitions_sth;
my $bans_sth;
my $seen_sth;
my $stats_sth;
my $names_sth;
my $ranks_sth;
my %last_ping_by_slot;
my @row;
my $rule_name;
my %rule_regex;
my %rule_penalty;
my $rule_response;
my %number_of_responses;
my %penalty_points;
my $partial = '';
my @banned_names;
my @announcements;
my $reset_slot;
my $most_recent_guid = 0;
my $most_recent_slot = 0;
my $most_recent_time = 0;
my $last_guid_sanity_check;
my $uptime = 0;
my %flood_protection;
my $first_blood = 1;
my %last_killed_by_name;
my %last_killed_by_guid;
my %last_kill_by_name;
my %last_kill_by_guid;
my %kill_spree;
my %best_spree;
my $next_announcement;
my $voting            = 0;
my $reactivate_voting = 0;
my $fly_timer         = 0;
my $ban_message_spam  = 0;
my $kick_message_spam = 0;
my %location_spoof;
my $gametype;
my $gamename;
my $mapname;
my $log_sync      = 0;
my $friendly_fire = 0;
my $killcam       = 1;
my $cod_version;
my $server_name;
my $max_clients     = 64;
my $min_ping        = 0;
my $max_ping        = 999;
my $max_rate        = 25000;
my $private_clients = 0;
my $pure            = 1;
my $voice           = 0;
my $fs_game;
my $antilag = 1;
my $protocol;
my $allow_anonymous = 0;
my $flood_protect   = 1;
my $last_guid0_audit;
my %ignore;
my $ftp_lines       = 0;
my $ftp_verbose     = 1;
my $ftp_host        = '';
my $ftp_dirname     = '';
my $ftp_basename    = '';
my $ftp_tmpFileName = '';
my $ftp_currentEnd;
my $ftp_lastEnd;
my $ftp_type;
my $logfile_mode = 'local';
my @ftp_buffer;
my $ftp;
my $next_map;
my $next_gametype;
my $freshen_next_map_prediction = 1;
my $temporary;
my %description;
my $now_upmins  = 0;
my $last_upmins = 0;
my @affiliate_servers;
my $next_affiliate_announcement;
my %servername_cache;
my @remote_servers;
my $maximum_length = 512;
my $players_count  = 0;
my $vote_initiator;
my $vote_type;
my $vote_target;
my $vote_target_slot;
my $vote_string;
my $vote_started   = 0;
my $voted_yes      = 0;
my $voted_no       = 0;
my $voting_players = 0;
my $required_yes   = 0;
my $vote_time      = 0;

# turn on auto-flush for STDOUT
local $| = 1;

# initialize the timers
$time        = time;
$timestring  = scalar(localtime($time));
$currenttime = $timestring->strftime();
if ($currenttime =~ /^(\w+),\s(\d+)\s(\w+)\s(\d+)\s(\d+:\d+:\d+)\s(\w+)$/) { $currenttime = "$5 $6"; }    # Only display time and timezone
$currentdate            = $timestring->dmy(".");
$last_idlecheck         = $time;
$last_namecheck         = $time;
$last_guid0_audit       = $time;
$last_guid_sanity_check = $time;

# Read the configuration from the .cfg file.
&load_config_file($config_name);

# Open the server logfile for reading.
if ($logfile_mode eq 'local') {
	&open_server_logfile($config->{'server_logfile_name'});

	# Seek to the end of the logfile
	seek(LOGFILE, 0, 2);
}
else { &ftp_connect; }

# use interval for first announcement that defined in config
$next_announcement = $time + (60 * ($config->{'interval_min'} + int(rand($config->{'interval_max'} - $config->{'interval_min'} + 1))));
$next_affiliate_announcement = $time + $config->{'affiliate_server_announcement_interval'};

# Initialize the database tables if they do not exist
&initialize_databases;

# Prepare to dump all warnings to log, very useful for debugging
local $SIG{__WARN__} = sub {
	my $message = shift;
	return if $WARNS{$message}++;
	&log_to_file('logs/warnings.log', "WARNING: $message");
};

# Startup message
print "================================================================================\n";

print "                     Server babysitter for Call of Duty 2\n";
print "                          Version $version\n";
print "                            Author - smugllama\n";
print "                       Additional work - VoroN\n\n";

print "                       RCON-module based on KKrcon\n";
print "                       http://kkrcon.sourceforge.net\n\n";

print "                    IP-Geolocation provided by MaxMind\n";
print "                         http://www.maxmind.com\n\n";

print "                    Support for remote FTP log-files\n";
print "                    based on ftptail from Will Moffat\n";
print "                  http://hamstersoup.wordpress.com/ftptail\n\n";

print "                 Original version of NannyBot available at:\n";
print "                      http://smaert.com/nannybot.zip\n\n";

print "                     Latest version available at:\n";
print "                    https://github.com/voron00/Nanny\n\n";

print "================================================================================\n";

# create the rcon control object - this is how we send commands to the server
my $rcon = new KKrcon(
	Host     => $config->{'ip'},
	Port     => $config->{'port'},
	Password => $config->{'rcon_pass'},
	Type     => 'old'
);

# tell the server that we want the game logfiles flushed to disk after every line.
$temporary = &rcon_query('g_logSync');
if ($temporary =~ /\"g_logSync\" is: \"(\d+)\^7\"/mi) {
	$log_sync = $1;
	if ($log_sync == 1) { print "logSync is currently turned ON\n"; }
	else {
		print "WARNING: logSync is currently turned OFF, turning it ON and restarting the map\n";
		&rcon_command("g_logSync 1");
		&rcon_command("map_restart");
	}
}
else { print "WARNING: unable to parse g_logSync: $temporary\n"; }

# Ask which version of CoD2 server is currently running
$temporary = &rcon_query('shortversion');
if ($temporary =~ /\"shortversion\" is: \"([\d.]+)\^7\"/mi) {
	$cod_version = $1;
	if ($cod_version =~ /./) { print "CoD2 version is: $cod_version\n"; }
}
else { print "WARNING: unable to parse shortversion: $temporary\n"; }

# Ask the server what it's official name is
$temporary = &rcon_query("sv_hostname");
if ($temporary =~ /\"sv_hostname\" is: \"([^\"]+)\^7\"/mi) {
	$server_name = $1;
	if ($server_name =~ /./) { print "Server name is: $server_name\n"; }
}
else { print "WARNING: unable to parse sv_hostname: $temporary\n"; }

# Ask the server if voting is currently turned on or off
$temporary = &rcon_query("g_allowVote");
if ($temporary =~ /\"g_allowVote\" is: \"(\d+)\^7\"/mi) {
	$voting = $1;
	if   ($voting) { print "Voting is currently turned ON\n"; }
	else           { print "Voting is currently turned OFF\n"; }
}
else { print "WARNING: unable to parse g_allowVote: $temporary\n"; }

# Ask which map is now present
$temporary = &rcon_query('mapname');
if ($temporary =~ /\"mapname\" is: \"(\w+)\^7\"/mi) {
	$mapname = $1;
	if ($mapname =~ /./) { print "Current map is: $mapname\n"; }
}
else { print "WARNING: unable to parse mapname: $temporary\n"; }

# Ask which game type is now present
$temporary = &rcon_query('g_gametype');
if ($temporary =~ /\"g_gametype\" is: \"(\w+)\^7\"/mi) {
	$gametype = $1;
	if ($gametype =~ /./) { print "Current gametype is: $gametype\n"; }
}
else { print "WARNING: unable to parse g_gametype: $temporary\n"; }

# Do rcon status now to prevent some undefined variables
&status;
$last_rconstatus = $time;

# Main Loop
while (1) {

	if   ($logfile_mode eq 'local') { $line = <LOGFILE>; }
	else                            { $line = &ftp_get_line; }

	# We have a new line from the logfile.
	if (defined($line)) {

		# make sure our line is complete.
		if ($line !~ /\n/) {

			# incomplete, save this for next time.
			$partial = $line;
			next;
		}

		# if we have any previous leftovers, prepend them.
		if ($partial ne '') {
			$line    = $partial . $line;
			$partial = '';
		}

		# Strip the timestamp from the begining
		if ($line =~ /^\s{0,2}(\d+:\d+)\s+(.*)/) {
			($uptime, $line) = ($1, $2);

			# BEGIN: SERVER CRASH / RESTART detection
			# detect when the uptime gets smaller.
			if ($uptime =~ /^(\d+):/) {
				$now_upmins = $1;
				if ($now_upmins < $last_upmins) {
					&reset;
					print "SERVER CRASH/RESTART DETECTED, RESETTING...\n";
				}
				$last_upmins = $now_upmins;
			}

			# END: SERVER CRASH / RESTART detection
		}

		# Strip the newline and any trailing space from the end.
		$line =~ s/\s+$//;

		# hold onto the first character of the line
		# doing single character eq is faster than regex
		$first_char = substr($line, 0, 1);

		# Which class of event is the line we just read?
		if ($first_char eq 'K') {

			# A "KILL" Event has happened
			if ($line =~ /^K;(\d+);(\d+);(allies|axis|);([^;]+);(\d*);([\d\-]+);(allies|axis|world|spectator|);([^;]*);(\w+);(\d+);(\w+);(\w+)/) {
				($victim_guid, $victim_slot, $victim_team, $victim_name, $attacker_guid, $attacker_slot, $attacker_team, $attacker_name, $attacker_weapon, $damage, $damage_type, $damage_location) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);

				# the RIDDLER fix, try #1
				$attacker_name =~ s/\s+$//;
				$victim_name =~ s/\s+$//;
				if (($attacker_guid) and ($attacker_name)) {
					&cache_guid_to_name($attacker_guid, $attacker_name);
				}
				if (($victim_guid) and ($victim_name)) {
					&cache_guid_to_name($victim_guid, $victim_name);
				}
				$last_activity_by_slot{$attacker_slot} = $time;
				&update_name_by_slot($attacker_name, $attacker_slot);
				&update_name_by_slot($victim_name,   $victim_slot);
				$guid_by_slot{$attacker_slot} = $attacker_guid;
				$guid_by_slot{$victim_slot}   = $victim_guid;

				if ($attacker_slot ne $victim_slot) {
					$last_killed_by_name{$victim_slot} = $attacker_name;
					$last_killed_by_guid{$victim_slot} = $attacker_guid;
					if ($last_killed_by_name{$victim_slot} =~ /\^\^\d\d/) {
						$last_killed_by_name{$victim_slot} = &strip_color($last_killed_by_name{$victim_slot});
					}
					$last_kill_by_name{$attacker_slot} = $victim_name;
					$last_kill_by_guid{$attacker_slot} = $victim_guid;
					if ($last_kill_by_name{$attacker_slot} =~ /\^\^\d\d/) {
						$last_kill_by_name{$attacker_slot} = &strip_color($last_kill_by_name{$attacker_slot});
					}
				}

				# Glitch Server Mode
				if ($config->{'glitch_server_mode'}) {
					print "GLITCH SERVER MODE: $name_by_slot{$attacker_slot} killed someone. Kicking!\n";
					&rcon_command("say $name_by_slot{$attacker_slot}^7: " . $config->{'glitch_kill_kick_message'});
					sleep 1;
					&rcon_command("clientkick $attacker_slot");
					&log_to_file('logs/kick.log', "GLITCH_KILL: Murderer! Kicking $attacker_name for killing other people");
				}

				# Track the kill stats for the killer
				if (($attacker_guid) and ($attacker_slot ne $victim_slot)) {
					$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE guid=?");
					$stats_sth->execute($attacker_guid)
					  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
					@row = $stats_sth->fetchrow_array;
					if ($row[0]) {
						if ($damage_location eq 'head') {
							$stats_sth = $stats_dbh->prepare("UPDATE stats SET kills=?,headshots=? WHERE guid=?");
							$stats_sth->execute(($row[2] + 1), ($row[4] + 1), $attacker_guid) or &die_nice("Unable to do update\n");
						}
						else {
							$stats_sth = $stats_dbh->prepare("UPDATE stats SET kills=? WHERE guid=?");
							$stats_sth->execute(($row[2] + 1), $attacker_guid)
							  or &die_nice("Unable to do update\n");
						}
					}
					else {
						$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)");
						if ($damage_location eq 'head') {
							$stats_sth->execute($attacker_guid, 1, 0, 1)
							  or &die_nice("Unable to do insert\n");
						}
						else {
							$stats_sth->execute($attacker_guid, 1, 0, 0)
							  or &die_nice("Unable to do insert\n");
						}
					}

					# Grenade Kills
					if ($damage_type eq 'MOD_GRENADE_SPLASH') {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET grenade_kills = grenade_kills + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}

					# Pistol Kills
					if ($attacker_weapon =~ /^(webley|colt|luger|TT30)_mp$/) {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET pistol_kills = pistol_kills + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}

					# Bash / Melee Kills
					if ($damage_type eq 'MOD_MELEE') {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET bash_kills = bash_kills + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}

					# Shotgun Kills
					if ($attacker_weapon eq 'shotgun_mp') {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET shotgun_kills = shotgun_kills + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}

					# Sniper Kills
					if ($attacker_weapon =~ /^(enfield_scope|springfield|mosin_nagant_sniper|kar98k_sniper)_mp$/) {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET sniper_kills = sniper_kills + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}

					# Rifle Kills
					if ($attacker_weapon =~ /^(enfield|m1garand|m1carbine|mosin_nagant|SVT40|kar98k|g43)_mp$/) {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET rifle_kills = rifle_kills + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}

					# Machinegun Kills
					if ($attacker_weapon =~ /^(sten|thompson|bren|greasegun|bar|PPS42|ppsh|mp40|mp44|30cal_stand|mg42_bipod_stand)_mp$/) {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET machinegun_kills = machinegun_kills + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}
				}

				# Track the death stats for the victim
				if (($victim_guid) and ($victim_slot ne $attacker_slot)) {
					$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE guid=?");
					$stats_sth->execute($victim_guid)
					  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
					@row = $stats_sth->fetchrow_array;
					if ($row[0]) {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET deaths=? WHERE guid=?");
						$stats_sth->execute(($row[3] + 1), $victim_guid)
						  or &die_nice("Unable to do update\n");
					}
					else {
						$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)");
						$stats_sth->execute($victim_guid, 0, 1, 0)
						  or &die_nice("Unable to do insert\n");
					}
				}

				# End of kill-stats tracking
				# print the kill to the screen
				if ($damage_location eq 'head') {
					if ($config->{'show_headshots'}) {
						print "HEADSHOT: $name_by_slot{$attacker_slot} killed $name_by_slot{$victim_slot} - HEADSHOT!\n";
					}
					&log_to_file('logs/kills.log', "HEADSHOT: $name_by_slot{$attacker_slot} killed $name_by_slot{$victim_slot} - HEADSHOT!");
				}
				else {
					if ($victim_slot eq $attacker_slot) {
						&log_to_file('logs/kills.log', "SUICIDE: $name_by_slot{$attacker_slot} killed himself");
					}
					elsif ($damage_type eq 'MOD_FALLING') {
						&log_to_file('logs/kills.log', "FALL: $name_by_slot{$victim_slot} fell to their death");
					}
					else {
						&log_to_file('logs/kills.log', "KILL: $name_by_slot{$attacker_slot} killed $name_by_slot{$victim_slot}");
					}
					if ($config->{'show_kills'}) {
						if ($victim_slot eq $attacker_slot) {
							print "SUICIDE: $name_by_slot{$attacker_slot} killed himself\n";
						}
						elsif ($damage_type eq 'MOD_FALLING') {
							print "FALL: $name_by_slot{$victim_slot} fell to their death\n";
						}
						else {
							print "KILL: $name_by_slot{$attacker_slot} killed $name_by_slot{$victim_slot}\n";
						}
					}
				}

				# First Blood
				if (    ($config->{'first_blood'})
					and ($first_blood == 0)
					and ($damage_type ne 'MOD_SUICIDE')
					and ($damage_type ne 'MOD_FALLING')
					and ($damage_type ne 'MOD_TRIGGER_HURT')
					and ($attacker_team ne 'world')
					and ($attacker_slot ne $victim_slot))
				{
					$first_blood = 1;
					&rcon_command("say ^1FIRST BLOOD^7: $name_by_slot{$attacker_slot} ^7killed $name_by_slot{$victim_slot}");
					print "FIRST BLOOD: $name_by_slot{$attacker_slot} killed $name_by_slot{$victim_slot}\n";

					# First blood stats tracking
					if ($attacker_guid) {
						$stats_sth = $stats_dbh->prepare("UPDATE stats SET first_bloods = first_bloods + 1 WHERE guid=?");
						$stats_sth->execute($attacker_guid)
						  or &die_nice("Unable to update stats\n");
					}
				}

				# Killing Spree
				if (    ($config->{'killing_sprees'})
					and ($damage_type ne 'MOD_SUICIDE')
					and ($damage_type ne 'MOD_FALLING')
					and ($damage_type ne 'MOD_TRIGGER_HURT')
					and ($attacker_team ne 'world')
					and ($attacker_slot ne $victim_slot))
				{
					if (!defined($kill_spree{$attacker_slot})) {
						$kill_spree{$attacker_slot} = 1;
					}
					else { $kill_spree{$attacker_slot} += 1; }
					if (defined($kill_spree{$victim_slot})) {
						if (!defined($best_spree{$victim_slot})) {
							$best_spree{$victim_slot} = 0;
						}
						if (    ($kill_spree{$victim_slot} > 2)
							and ($kill_spree{$victim_slot} > $best_spree{$victim_slot}))
						{
							$best_spree{$victim_slot} = $kill_spree{$victim_slot};
							$stats_sth = $stats_dbh->prepare("SELECT best_killspree FROM stats WHERE guid=?");
							$stats_sth->execute($victim_guid)
							  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
							@row = $stats_sth->fetchrow_array;

							if (    ($victim_guid)
								and (defined($row[0]))
								and ($row[0] < $best_spree{$victim_slot}))
							{
								$stats_sth = $stats_dbh->prepare("UPDATE stats SET best_killspree=? WHERE guid=?");
								$stats_sth->execute($best_spree{$victim_slot}, $victim_guid)
								  or &die_nice("Unable to update stats\n");
								&rcon_command("say $name_by_slot{$attacker_slot} ^7has stopped ^2*^1BEST^2* ^7killing spree of $name_by_slot{$victim_slot} ^7who killed ^6$kill_spree{$victim_slot} ^7players");
							}
							else {
								&rcon_command("say $name_by_slot{$attacker_slot} ^7has stopped killing spree of $name_by_slot{$victim_slot} ^7who killed ^6$kill_spree{$victim_slot} ^7players");
							}
						}
					}
					$kill_spree{$victim_slot} = 0;
					$best_spree{$victim_slot} = 0;
				}

				# End of Kill-Spree section
			}
			else {
				print "WARNING: unrecognized syntax for kill line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 'D') {

			# A "DAMAGE" event has happened.
			if ($line =~ /^D;(\d+);(\d+);(allies|axis|);([^;]+);(\d*);([\d\-]+);(allies|axis|world|spectator|);([^;]*);(\w+);(\d+);(\w+);(\w+)/) {
				($victim_guid, $victim_slot, $victim_team, $victim_name, $attacker_guid, $attacker_slot, $attacker_team, $attacker_name, $attacker_weapon, $damage, $damage_type, $damage_location) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);
				if (($attacker_guid) and ($attacker_name)) {
					&cache_guid_to_name($attacker_guid, $attacker_name);
				}
				if (($victim_guid) and ($victim_name)) {
					&cache_guid_to_name($victim_guid, $victim_name);
				}
				$last_activity_by_slot{$attacker_slot} = $time;
				&update_name_by_slot($attacker_name, $attacker_slot);
				&update_name_by_slot($victim_name,   $victim_slot);
				$guid_by_slot{$attacker_slot} = $attacker_guid;
				$guid_by_slot{$victim_slot}   = $victim_guid;
			}
			else {
				print "WARNING: unrecognized syntax for damage line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 'J') {

			# A "JOIN" Event has happened
			# WARNING:  This join does not only mean they just connected to the server
			# it can also mean that the level has changed.
			if ($line =~ /^J;(\d+);(\d+);(.*)/) {
				($guid, $slot, $name) = ($1, $2, $3);

				# cache the guid and name
				if (($guid) and ($name)) {
					&cache_guid_to_name($guid, $name);
				}
				$most_recent_guid             = $guid;
				$most_recent_slot             = $slot;
				$most_recent_time             = $time;
				$last_activity_by_slot{$slot} = $time;
				$idle_warn_level{$slot}       = 0;
				$guid_by_slot{$slot}          = $guid;
				&update_name_by_slot($name, $slot);
				$ip_by_slot{$slot}          = 'not_yet_known';
				$spam_count{$slot}          = 0;
				$spam_last_said{$slot}      = &random_pwd(16);
				$ping_by_slot{$slot}        = 0;
				$last_ping_by_slot{$slot}   = 0;
				$kill_spree{$slot}          = 0;
				$best_spree{$slot}          = 0;
				$last_killed_by_name{$slot} = 'none';
				$last_killed_by_guid{$slot} = 0;
				$last_kill_by_name{$slot}   = 'none';
				$last_kill_by_guid{$slot}   = 0;

				if ($gametype ne 'sd') {
					$penalty_points{$slot} = 0;
					$ignore{$slot}         = 0;
				}
				if (    ($config->{'show_game_joins'})
					and ($gametype ne 'sd'))
				{
					&rcon_command("say $name_by_slot{$slot} ^7has joined the game");
				}
				if ($config->{'show_joins'}) {
					print "JOIN: $name_by_slot{$slot} has joined the game\n";
				}

				# Check for banned GUID
				if ($guid) { &banned_guid_check($slot); }
			}
			else {
				print "WARNING: unrecognized syntax for join line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 'Q') {

			# A "QUIT" Event has happened
			if ($line =~ /^Q;(\d+);(\d+);(.*)/) {
				($guid, $slot, $name) = ($1, $2, $3);

				# cache the guid and name
				if (($guid) and ($name)) {
					&cache_guid_to_name($guid, $name);
				}
				&update_name_by_slot($name, $slot);
				if ($config->{'show_game_quits'}) {
					&rcon_command("say $name_by_slot{$slot} ^7has left the game");
				}
				if ($config->{'show_quits'}) {
					print "QUIT: $name_by_slot{$slot} has left the game\n";
				}
				&update_name_by_slot('SLOT_EMPTY', $slot);
				$last_activity_by_slot{$slot} = 'gone';
				$idle_warn_level{$slot}       = 0;
				$ip_by_slot{$slot}            = 'SLOT_EMPTY';
				$guid_by_slot{$slot}          = 0;
				$spam_count{$slot}            = 0;
				$ping_by_slot{$slot}          = 0;
				$last_ping_by_slot{$slot}     = 0;
				$penalty_points{$slot}        = 0;
				$last_killed_by_name{$slot}   = 'none';
				$last_killed_by_guid{$slot}   = 0;
				$last_kill_by_name{$slot}     = 'none';
				$last_kill_by_guid{$slot}     = 0;
				$kill_spree{$slot}            = 0;
				$best_spree{$slot}            = 0;
				$ignore{$slot}                = 0;
			}
			else {
				print "WARNING: unrecognized syntax for quit line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 's') {

			# a "SAY" event has happened
			if ($line =~ /^say;(\d+);(\d+);([^;]+);(.*)/) {
				($guid, $slot, $name, $message) = ($1, $2, $3, $4);
				$last_activity_by_slot{$slot} = $time;
				$guid_by_slot{$slot}          = $guid;
				$message =~ s/^\x15//;
				&chat('SAY');
			}

			# a "SAY" with only Unicode characters in name event has happened
			elsif ($line =~ /^say;(\d+);(\d+);;(.*)/) {
				($guid, $slot, $name, $message) = ($1, $2, '', $3);
				$last_activity_by_slot{$slot} = $time;
				$guid_by_slot{$slot}          = $guid;
				$message =~ s/^\x15//;
				&chat('SAY');
			}

			# a "SAYTEAM" event has happened
			elsif ($line =~ /^sayteam;(\d+);(\d+);([^;]+);(.*)/) {
				($guid, $slot, $name, $message) = ($1, $2, $3, $4);
				$last_activity_by_slot{$slot} = $time;
				$guid_by_slot{$slot}          = $guid;
				$message =~ s/^\x15//;
				&chat('SAYTEAM');
			}

			# a "SAYTEAM" with only Unicode characters in name event has happened
			elsif ($line =~ /^sayteam;(\d+);(\d+);;(.*)/) {
				($guid, $slot, $name, $message) = ($1, $2, '', $3);
				$last_activity_by_slot{$slot} = $time;
				$guid_by_slot{$slot}          = $guid;
				$message =~ s/^\x15//;
				&chat('SAYTEAM');
			}
			else {
				print "WARNING: unrecognized syntax for say line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 't') {

			# a "tell" (private message) event has happened
			if ($line =~ /^tell;(\d+);(\d+);([^;]+);\d+;\d+;[^;]+;(.*)/) {
				($guid, $slot, $name, $message) = ($1, $2, $3, $4);
				$last_activity_by_slot{$slot} = $time;
				$guid_by_slot{$slot}          = $guid;
				$message =~ s/^\x15//;
				&chat('TELL');
			}

			# a "tell" (private message) with only Unicode characters in name event has happened
			elsif ($line =~ /^tell;(\d+);(\d+);;\d+;\d+;[^;]+;(.*)/) {
				($guid, $slot, $name, $message) = ($1, $2, '', $3);
				$last_activity_by_slot{$slot} = $time;
				$guid_by_slot{$slot}          = $guid;
				$message =~ s/^\x15//;
				&chat('TELL');
			}

			# a "tell" (private message) with only Unicode characters in name to name with only Unicode characters in name event has happened
			elsif ($line =~ /^tell;(\d+);(\d+);;\d+;\d+;;(.*)/) {
				($guid, $slot, $name, $message) = ($1, $2, '', $3);
				$last_activity_by_slot{$slot} = $time;
				$guid_by_slot{$slot}          = $guid;
				$message =~ s/^\x15//;
				&chat('TELL');
			}
			else {
				print "WARNING: unrecognized syntax for tell line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 'W') {

			# a "WEAPON" Event has happened
			if ($line =~ /^Weapon;(\d+);(\d+);([^;]*);(\w+)$/) {
				($guid, $slot, $name, $weapon) = ($1, $2, $3, $4);

				# cache the guid and name
				if (($guid) and ($name)) {
					&cache_guid_to_name($guid, $name);
				}
				$last_activity_by_slot{$slot} = $time;
				&update_name_by_slot($name, $slot);
				$guid_by_slot{$slot} = $guid;
			}

			# a "Round Win" Event has happened
			elsif ($line =~ /^W;([^;]*);(\d+);([^;]*)/) {
				($attacker_team, $guid, $name) = ($1, $2, $3);

				# cache the guid and name
				if (($guid) and ($name)) {
					&cache_guid_to_name($guid, $name);
				}
				if (    (defined($attacker_team))
					and ($attacker_team =~ /./))
				{
					print "GAME OVER: $attacker_team have WON this game of $gametype on $mapname\n";
				}
				else {
					print "GAME OVER: $name has WON this game of $gametype on $mapname\n";
				}

				# BEGIN: Update best_killspree stats
				foreach $slot (keys %kill_spree) {
					if (defined($kill_spree{$slot})
						and $kill_spree{$slot} > 2)
					{
						$stats_sth = $stats_dbh->prepare("SELECT best_killspree FROM stats WHERE guid=?");
						$stats_sth->execute($guid_by_slot{$slot})
						  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
						@row = $stats_sth->fetchrow_array;
						if (    ($guid_by_slot{$slot})
							and (defined($row[0]))
							and ($row[0] < $kill_spree{$slot}))
						{
							$stats_sth = $stats_dbh->prepare("UPDATE stats SET best_killspree=? WHERE guid=?");
							$stats_sth->execute($kill_spree{$slot}, $guid_by_slot{$slot}) or &die_nice("Unable to update stats\n");
						}
					}
				}

				# END: Update best_killspree stats
			}

			# sometimes this line happens on sd, when there are no players and round has ended
			elsif ($line =~ /^W;([^;]*)/) {
				$attacker_team = $1;
				if (    (defined($attacker_team))
					and ($attacker_team =~ /./))
				{
					print "GAME OVER: $attacker_team have WON this game of $gametype on $mapname\n";
				}
			}
			else {
				print "WARNING: unrecognized syntax for Weapon/Round Win line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 'L') {

			# a "Round Lose" Event has happened
			if ($line =~ /^L;([^;]*);(\d+);([^;]*)/) {
				($attacker_team, $guid, $name) = ($1, $2, $3);

				# cache the guid and name
				if (($guid) and ($name)) {
					&cache_guid_to_name($guid, $name);
				}
				if (    (defined($attacker_team))
					and ($attacker_team =~ /./))
				{
					print "GAME OVER: $attacker_team have LOST this game of $gametype on $mapname\n";
				}
			}

			# sometimes this line happens on sd, when there are no players and round has ended
			elsif ($line =~ /^L;([^;]*)/) {
				$attacker_team = $1;
				if (    (defined($attacker_team))
					and ($attacker_team =~ /./))
				{
					print "GAME OVER: $attacker_team have LOST this game of $gametype on $mapname\n";
				}
			}
			else {
				print "WARNING: unrecognized syntax for Round Loss line:\n\t$line\n";
			}
		}
		elsif ($first_char eq 'A') {
			if ($line =~ /^A;(\d+);(\d+);(\w+);(.*);bomb_plant/) {
				($guid, $slot, $attacker_team, $name) = ($1, $2, $3, $4);

				# cache the guid and name
				if (($guid) and ($name)) {
					&cache_guid_to_name($guid, $name);
				}
				$last_activity_by_slot{$slot} = $time;
				&update_name_by_slot($name, $slot);
				$guid_by_slot{$slot} = $guid;
				print "BOMB: $name_by_slot{$slot} planted the bomb\n";

				# bomb plants stats tracking
				if ($guid) {
					$stats_sth = $stats_dbh->prepare("UPDATE stats SET bomb_plants = bomb_plants + 1 WHERE guid=?");
					$stats_sth->execute($guid)
					  or &die_nice("Unable to update stats\n");
				}
			}
			elsif ($line =~ /^A;(\d+);(\d+);(\w+);(.*);bomb_defuse/) {
				($guid, $slot, $attacker_team, $name) = ($1, $2, $3, $4);

				# cache the guid and name
				if (($guid) and ($name)) {
					&cache_guid_to_name($guid, $name);
				}
				$last_activity_by_slot{$slot} = $time;
				&update_name_by_slot($name, $slot);
				$guid_by_slot{$slot} = $guid;
				print "BOMB: $name_by_slot{$slot} defused the bomb\n";

				# bomb defuses stats tracking
				if ($guid) {
					$stats_sth = $stats_dbh->prepare("UPDATE stats SET bomb_defuses = bomb_defuses + 1 WHERE guid=?");
					$stats_sth->execute($guid)
					  or &die_nice("Unable to update stats\n");
				}
			}
			else { print "WARNING: unrecognized A line format:\n\t$line\n"; }
		}
		elsif ($first_char eq 'I') {

			# Init Level
			if ($line =~ /\\fs_game\\([^\\]+)/) {
				$fs_game = $1;
			}
			if ($line =~ /\\g_antilag\\([^\\]+)/) {
				$antilag = $1;
			}
			if ($line =~ /\\g_gametype\\([^\\]+)/) {
				$gametype = $1;
			}
			if ($line =~ /\\gamename\\([^\\]+)/) {
				$gamename = $1;
			}
			if ($line =~ /\\mapname\\([^\\]+)/) {
				$mapname = $1;
			}
			if ($line =~ /\\protocol\\([^\\]+)/) {
				$protocol = $1;
			}
			if ($line =~ /\\scr_friendlyfire\\([^\\]+)/) {
				$friendly_fire = $1;
			}
			if ($line =~ /\\scr_killcam\\([^\\]+)/) {
				$killcam = $1;
			}
			if ($line =~ /\\shortversion\\([^\\]+)/) {
				$cod_version = $1;
			}
			if ($line =~ /\\sv_allowAnonymous\\([^\\]+)/) {
				$allow_anonymous = $1;
			}
			if ($line =~ /\\sv_floodProtect\\([^\\]+)/) {
				$flood_protect = $1;
			}
			if ($line =~ /\\sv_hostname\\([^\\]+)/) {
				$server_name = $1;
			}
			if ($line =~ /\\sv_maxclients\\([^\\]+)/) {
				$max_clients = $1;
			}
			if ($line =~ /\\sv_maxPing\\([^\\]+)/) {
				$max_ping = $1;
			}
			if ($line =~ /\\sv_maxRate\\([^\\]+)/) {
				$max_rate = $1;
			}
			if ($line =~ /\\sv_minPing\\([^\\]+)/) {
				$min_ping = $1;
			}
			if ($line =~ /\\sv_privateClients\\([^\\]+)/) {
				$private_clients = $1;
			}
			if ($line =~ /\\sv_pure\\([^\\]+)/) {
				$pure = $1;
			}
			if ($line =~ /\\sv_voice\\([^\\]+)/) {
				$voice = $1;
			}

			print "MAP STARTING: $mapname $gametype\n";

			# prepare for First Blood
			$first_blood = 0;

			# anti-vote-rush
			# first, look up the game-type so we can exempt S&D
			if (    ($voting)
				and ($config->{'anti_vote_rush'})
				and ($gametype ne 'sd'))
			{
				print "ANTI-VOTE-RUSH: Turned off voting for 25 seconds...\n";
				&rcon_command("g_allowVote 0");
				$reactivate_voting = $time + 25;
			}

			# Buy some time so we don't do an rcon status during a level change
			# Also, on SD, we need to do rcon status right after a round restart, so we add this
			if   ($gametype eq 'sd') { $last_rconstatus = $time - 29; }
			else                     { $last_rconstatus = $time; }

			# Update next map prediction
			$freshen_next_map_prediction = 1;
		}
		elsif ($first_char eq 'S') {

			# Server Shutdown - Triggers when the server shuts down?
		}
		elsif ($first_char eq '-') {

			# Line Break
		}
		elsif ($first_char eq 'E') {

			# Exit level - what is the difference between this and a shutdown?
			# This happens much less frequently than a Shutdown Game event.
			# This may be a game server shutdown, not just a level ending.
		}
		elsif (($first_char eq chr(13)) or ($first_char eq '')) {

			# Empty Line
		}
		else {
			# Unknown line
			print "UNKNOWN LINE: $first_char and $line\n";
			&log_to_file('logs/warnings.log', "UNKNOWN LINE: $first_char and $line\n");
		}
	}
	else {
		# We have reached the end of the logfile.
		# Delay some time so we aren't constantly hammering this loop
		usleep(100000);

		# cache the time to limit the number of syscalls
		$time        = time;
		$timestring  = scalar(localtime($time));
		$currenttime = $timestring->strftime();
		if ($currenttime =~ /^(\w+),\s(\d+)\s(\w+)\s(\d+)\s(\d+:\d+:\d+)\s(\w+)$/) { $currenttime = "$5 $6"; }    # Only display time and timezone
		$currentdate = $timestring->dmy(".");

		# Freshen the rcon status if it's time
		if (($time - $last_rconstatus) >= ($rconstatus_interval)) {
			$last_rconstatus = $time;
			&status;
		}

		# Anti-Idle check
		if ($config->{'antiidle'}) {
			if (($time - $last_idlecheck) >= ($idlecheck_interval)) {
				$last_idlecheck = $time;
				&idle_check;
			}
		}

		# Check for bad names if its time
		if (($time - $last_namecheck) >= ($namecheck_interval)) {
			$last_namecheck = $time;
			&check_player_names;
		}

		# Check if it's time to make our next announement yet.
		if (    ($time >= $next_announcement)
			and ($config->{'use_announcements'}))
		{
			$next_announcement = $time + (60 * ($config->{'interval_min'} + int(rand($config->{'interval_max'} - $config->{'interval_min'} + 1))));
			&make_announcement;
		}

		# Check if it's time to make our next affiliate server announement yet.
		if ($config->{'affiliate_server_announcements'}) {
			if ($time >= $next_affiliate_announcement) {
				$next_affiliate_announcement = $time + $config->{'affiliate_server_announcement_interval'};
				&make_affiliate_server_announcement;
			}
		}

		# Check to see if its time to reactivate voting
		if (($reactivate_voting) and ($time >= $reactivate_voting)) {
			$reactivate_voting = 0;
			if ($voting) {
				&rcon_command("g_allowVote 1");
				print "ANTI-VOTE-RUSH: Reactivated Voting...\n";
			}
		}

		# Check to see if its time to turn off !fly command
		if (($fly_timer) and ($time >= $fly_timer)) {
			$fly_timer = 0;
			&rcon_command("g_gravity 800");
			&rcon_command("say Enough flying for now, it's time to play normally");
		}

		# Ban message anti-spam
		if (($ban_message_spam) and ($time >= $ban_message_spam)) {
			$ban_message_spam = 0;
		}

		# Kick message anti-spam (penalty points)
		if (($kick_message_spam) and ($time >= $kick_message_spam)) {
			$kick_message_spam = 0;
		}

		# Check vote status
		if ($vote_started) {

			# Vote TIMEOUT
			if (($vote_time) and ($time >= $vote_time)) {
				&rcon_command("say Vote: $vote_string " . &description($vote_target) . "^7: ^1FAILED^7: Voted ^2YES^7: ^2$voted_yes^7, Voted ^1NO^7: ^1$voted_no");
				&log_to_file('logs/voting.log', "RESULTS: Vote FAILED: Reason: TIMEOUT, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
				&vote_cleanup;
			}

			# Vote PASS, required YES reached
			elsif ($voted_yes >= $required_yes) {
				&rcon_command("say Vote: $vote_string " . &description($vote_target) . "^7: ^2PASSED^7: Voted ^2YES^7: ^2$voted_yes^7, Voted ^1NO^7: ^1$voted_no");
				sleep 1;
				if ($vote_type eq 'kick') {
					if ($name_by_slot{$vote_target_slot} eq $vote_target) {
						&kick_command($vote_target);
						&log_to_file('logs/voting.log', "RESULTS: Vote PASSED: ACTION: Kicking $vote_target, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
					}
					else {
						&kick_command('#' . $vote_target_slot);
						&log_to_file('logs/voting.log', "RESULTS: Vote PASSED: ACTION: Kicking $name_by_slot{$vote_target_slot}, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
					}
				}
				elsif ($vote_type eq 'ban') {
					if ($name_by_slot{$vote_target_slot} eq $vote_target) {
						&tempban_command($vote_target);
						&log_to_file('logs/voting.log', "RESULTS: Vote PASSED: ACTION: Temporary banning $vote_target, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
					}
					else {
						&tempban_command('#' . $vote_target);
						&log_to_file('logs/voting.log', "RESULTS: Vote PASSED: ACTION: Temporary banning $name_by_slot{$vote_target_slot}, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
					}
				}
				elsif ($vote_type eq 'map') {
					&change_map($vote_target);
					&log_to_file('logs/voting.log', "RESULTS: Vote PASSED: ACTION: Changing map to $vote_target, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
				}
				elsif ($vote_type eq 'type') {
					&change_gametype($vote_target);
					&log_to_file('logs/voting.log', "RESULTS: Vote PASSED: ACTION: Changing gametype to $vote_target, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
				}
				&vote_cleanup;
			}

			# Vote FAIL, too many NO
			elsif ($voted_no >= $required_yes) {
				&rcon_command("say Vote: $vote_string " . &description($vote_target) . "^7: ^1FAILED^7: Voted ^2YES^7: ^2$voted_yes^7, Voted ^1NO^7: ^1$voted_no");
				&log_to_file('logs/voting.log', "RESULTS: Vote FAILED: Reason: Too many NO, YES NEEDED: $required_yes | Voted YES: $voted_yes | Voted NO: $voted_no");
				&vote_cleanup;
			}
		}

		# End of vote check
		# Check to see if it's time to audit a GUID 0 person
		if (    ($config->{'audit_guid0_players'})
			and (($time - $last_guid0_audit) >= ($guid0_audit_interval)))
		{
			$last_guid0_audit = $time;
			&check_guid_zero_players;
		}

		# Check to see if we need to predict the next level
		if ($freshen_next_map_prediction) { &next_map_prediction; }
	}
}

# End of main program

# Begin - subroutines

# BEGIN: load_config_file(file)
# Load the .cfg file
#  This routine parses the configuration file for directives.
sub load_config_file {
	my $config_file = shift;
	if (!defined($config_file)) {
		&die_nice("load_config_file called without an argument\n");
	}
	if (!-e $config_file) {
		&die_nice("config file does not exist: $config_file\n");
	}

	open(CONFIG, $config_file)
	  or &die_nice("$config_file file exists, but i couldnt open it.\n");

	my $config_name;
	my $config_val;
	my $command_name;
	my $temp;
	my $rule_name      = 'undefined';
	my $response_count = 1;
	my $regex_match;
	my $location;

	print "\nParsing config file: $config_file\n\n";

	while (defined($line = <CONFIG>)) {
		$line =~ s/\s+$//;
		if ($line =~ /^\s*(\w+)\s*=\s*(.*)/) {
			($config_name, $config_val) = ($1, $2);
			if ($config_name eq 'ip_address') {
				$config->{'ip'} = $config_val;
				if ($config_val eq 'localhost|loopback') {
					$config->{'ip'} = '127.0.0.1';
				}
				print "Server IP address: $config->{'ip'}\n";
			}
			elsif ($config_name eq 'port') {
				$config->{'port'} = $config_val;
				print "Server port number: $config->{'port'}\n";
			}
			elsif ($config_name eq 'rule_name') {
				$rule_name                       = $config_val;
				$response_count                  = 1;
				$number_of_responses{$rule_name} = 0;
			}
			elsif ($config_name eq 'location_spoofing') {
				if ($config_val =~ /(.*) = (.*)/) {
					$location_spoof{$1} = $2;
				}
				else {
					print "WARNING: invalid synatx for location_spoofing:\n";
					print "on line: $config_name = $config_val\n";
					print "\n\tINVALID syntax.  Check config file\n";
					print "\tUse the format:  location_spoofing = Name = Location\n";
				}
			}
			elsif ($config_name eq 'description') {
				if ($config_val =~ /(.*) = (.*)/) { $description{$1} = $2; }
				else {
					print "WARNING: invalid synatx for description:\n";
					print "on line: $config_name = $config_val\n";
					print "\n\tINVALID syntax.  Check config file\n";
					print "\tUse the format: description = term = Description\n";
				}
			}
			elsif ($config_name eq 'match_text') {
				$rule_regex{$rule_name} = $config_val;
			}
			elsif ($config_name eq 'penalty') {
				$rule_penalty{$rule_name} = $config_val;
			}
			elsif ($config_name eq 'response') {
				$number_of_responses{$rule_name} = $response_count;
				$rule_response->{$rule_name}->{$response_count++} = $config_val;
			}
			elsif ($config_name =~ /^auth_(\w+)/) {
				$command_name = $1;
				if (!defined($config->{'auth'}->{$command_name})) {
					$config->{'auth'}->{$command_name} = $config_val;
					if ($config_val =~ /disabled/i) {
						print "!$command_name command is DISABLED\n";
					}
					else {
						print "Allowing $config_val to use the $command_name command\n";
					}
				}
				else {
					$temp = $config->{'auth'}->{$command_name};
					$temp .= ',' . $config_val;
					$config->{'auth'}->{$command_name} = $temp;
					if ($config_val =~ /disabled/i) {
						print "\nWARNING:  $command_name is disabled and enabled.  Which is it?\n\n";
					}
					else {
						print "Also allowing $config_val to use the $command_name command\n";
					}
				}
			}
			elsif ($config_name eq 'rcon_pass') {
				$config->{'rcon_pass'} = $config_val;
				print "RCON password: " . '*' x length($config->{'rcon_pass'}) . "\n";
			}
			elsif ($config_name eq 'ftp_username') {
				$config->{'ftp_username'} = $config_val;
				print "FTP username: " . ($config->{'ftp_username'}) . "\n";
			}
			elsif ($config_name eq 'ftp_password') {
				$config->{'ftp_password'} = $config_val;
				print "FTP password: " . '*' x length($config->{'ftp_password'}) . "\n";
			}
			elsif ($config_name eq 'server_logfile') {
				$config->{'server_logfile_name'} = $config_val;
				print "Server logfile name: $config->{'server_logfile_name'}\n";
				my $file;
				if ($config_val =~ /ftp:\/\/([^\/]+)\/(.+)/) {

					# FTP url has been specified - remote FTP mode selected
					($ftp_host, $file, $logfile_mode) = ($1, $2, 'ftp');
					($ftp_dirname, $ftp_basename) =
					  (dirname($file), basename($file));
				}
			}
			elsif ($config_name eq 'ban_name') {
				push @banned_names, $config_val;
				print "Banned player Name: $config_val\n";
			}
			elsif ($config_name eq 'announcement') {
				push @announcements, $config_val;
				print "Announcement: $config_val\n";
			}
			elsif ($config_name eq 'affiliate_server') {
				push @affiliate_servers, $config_val;
				print "Affiliate Server: $config_val\n";
			}
			elsif ($config_name eq 'remote_server') {
				push @remote_servers, $config_val;
				if ($config_val =~ /^([\d\.]+):(\d+):(.*)$/) {
					my ($ip_address, $port, $password) = ($1, $2, $3);
					print "Remote Server: $1:$2:" . '*' x length($3) . "\n";
				}
			}
			elsif ($config_name =~ /^(audit_guid0_players|antispam|antiidle|glitch_server_mode|ping_enforcement|999_quick_kick|flood_protection|killing_sprees|bad_shots|nice_shots|first_blood|anti_vote_rush|ban_name_thieves|affiliate_server_announcements|use_passive_ftp|guid_sanity_check|use_announcements|use_responses)$/) {
				if ($config_val =~ /yes|1|on|enable/i) {
					$config->{$config_name} = 1;
				}
				else { $config->{$config_name} = 0; }
				print "$config_name: " . $config->{$config_name} . "\n";
			}
			elsif ($config_name =~ 'interval_m[ia][nx]|banned_name_warn_message_[12]|banned_name_kick_message|max_ping|glitch_kill_kick_message|anti(spam|idle)_warn_(level|message)_[12]|anti(spam|idle)_kick_(level|message)|ftp_(username|password|refresh_time)|affiliate_server_announcement_interval') {
				$config->{$config_name} = $config_val;
				print "$config_name: " . $config->{$config_name} . "\n";
			}
			elsif ($config_name =~ /show_(joins|game_joins|game_quits|quits|kills|headshots|talk|rcon)/) {
				if ($config_val =~ /yes|1|on/i) {
					$config->{$config_name} = 1;
				}
				else { $config->{$config_name} = 0; }
				print "$config_name: " . $config->{$config_name} . "\n";
			}
			else {
				print "\nWARNING: unrecognized config file directive:\n";
				print "\toffending line: $config_name = $config_val\n\n";
			}
		}
	}

	close CONFIG;

	# idiot gates:  Make sure essential variables are defined.
	if (!defined($config->{'ip'})) {
		&die_nice("Config File: ip_address is not defined\tCheck the config file: $config_file\n");
	}
	if (!defined($config->{'rcon_pass'})) {
		&die_nice("Config File: rcon_pass is not defined\tCheck the config file: $config_file\n");
	}

	print "\nFinished parsing config: $config_file\n\n";

}

# END: load_config_file

# BEGIN: die_nice(message)
sub die_nice {
	my $message = shift;
	if ((!defined($message)) or ($message !~ /./)) {
		$message = 'default die_nice message.\n\n';
	}
	print "\nCritical Error: $message\n\n";
	&log_to_file('logs/error.log', "CRITICAL ERROR: $message");
	-e $ftp_tmpFileName and unlink($ftp_tmpFileName);
	exit 1;
}

# END: die_nice

# BEGIN: open_server_logfile(logfile)
sub open_server_logfile {
	my $log_file = shift;
	if (!defined($log_file)) {
		&die_nice("open_server_logfile called without an argument\n");
	}
	if (!-e $log_file) {
		&die_nice("open_server_logfile file does not exist: $log_file\n");
	}
	print "Opening $log_file for reading...\n\n";
	open(LOGFILE, $log_file) or &die_nice("unable to open $log_file: $!\n");
}

# END: open_server_logfile

# BEGIN: initialize_databases
sub initialize_databases {
	my %tables;
	my $cmd;
	my $result_code;

	# populate the list of tables already in the databases.
	$guid_to_name_sth = $guid_to_name_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$guid_to_name_sth->execute
	  or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
	foreach ($guid_to_name_sth->fetchrow_array) { $tables{$_} = $_; }

	# The GUID to NAME database
	if ($tables{'guid_to_name'}) {
		print "GUID <-> NAME database brought online\n\n";
	}
	else {
		print "Creating guid_to_name database...\n\n";
		$cmd         = "CREATE TABLE guid_to_name (id INTEGER PRIMARY KEY, guid INT(8), name VARCHAR(64));";
		$result_code = $guid_to_name_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $guid_to_name_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code rows were inserted\n";
		}
		$cmd         = "CREATE INDEX guid_to_name_index ON guid_to_name (id,guid,name)";
		$result_code = $guid_to_name_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $guid_to_name_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code rows were inserted\n";
		}
	}

	# The IP to GUID mapping table
	$ip_to_guid_sth = $ip_to_guid_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$ip_to_guid_sth->execute
	  or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
	foreach ($ip_to_guid_sth->fetchrow_array) { $tables{$_} = $_; }

	if ($tables{'ip_to_guid'}) {
		print "IP <-> GUID database brought online\n\n";
	}
	else {
		print "Creating ip_to_guid database...\n\n";
		$cmd         = "CREATE TABLE ip_to_guid (id INTEGER PRIMARY KEY, ip VARCHAR(15), guid INT(8));";
		$result_code = $ip_to_guid_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $ip_to_guid_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX ip_to_guid_index ON ip_to_guid (id,ip,guid)";
		$result_code = $ip_to_guid_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $ip_to_guid_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}

	# The IP to NAME mapping table
	$ip_to_name_sth = $ip_to_name_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$ip_to_name_sth->execute
	  or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
	foreach ($ip_to_name_sth->fetchrow_array) { $tables{$_} = $_; }

	if ($tables{'ip_to_name'}) {
		print "IP <-> NAME database brought online\n\n";
	}
	else {
		print "Creating ip_to_name database...\n\n";
		$cmd         = "CREATE TABLE ip_to_name (id INTEGER PRIMARY KEY, ip VARCHAR(15), name VARCHAR(64));";
		$result_code = $ip_to_name_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $ip_to_name_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX ip_to_name_index ON ip_to_name (id,ip,name)";
		$result_code = $ip_to_name_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $ip_to_name_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}

	# The seen database
	$seen_sth = $seen_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$seen_sth->execute
	  or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
	foreach ($seen_sth->fetchrow_array) { $tables{$_} = $_; }
	if ($tables{'seen'}) { print "seen database brought online\n\n"; }
	else {
		print "Creating seen database...\n\n";
		$cmd         = "CREATE TABLE seen (id INTEGER PRIMARY KEY, name VARCHAR(64), time INTEGER, saying VARCHAR(128));";
		$result_code = $seen_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $seen_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX seen_index ON seen (id,name,time,saying)";
		$result_code = $seen_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $seen_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}

	# The names database
	$names_sth = $names_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$names_sth->execute
	  or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	foreach ($names_sth->fetchrow_array) { $tables{$_} = $_; }
	if ($tables{'names'}) { print "names database brought online\n\n"; }
	else {
		print "Creating names database...\n\n";
		$cmd         = "CREATE TABLE names (id INTEGER PRIMARY KEY, name VARCHAR(64));";
		$result_code = $names_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $names_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX names_index ON names (id,name)";
		$result_code = $names_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $names_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}

	# The ranks database
	$ranks_sth = $ranks_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$ranks_sth->execute
	  or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
	foreach ($ranks_sth->fetchrow_array) { $tables{$_} = $_; }
	if ($tables{'ranks'}) { print "ranks database brought online\n\n"; }
	else {
		print "Creating ranks database...\n\n";
		$cmd         = "CREATE TABLE ranks (id INTEGER PRIMARY KEY, rank VARCHAR(64));";
		$result_code = $ranks_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $ranks_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX ranks_index ON ranks (id,rank)";
		$result_code = $ranks_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $ranks_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}

	# The bans database
	$bans_sth = $bans_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$bans_sth->execute
	  or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
	foreach ($bans_sth->fetchrow_array) { $tables{$_} = $_; }
	if ($tables{'bans'}) { print "bans database brought online\n\n"; }
	else {
		print "Creating bans database...\n\n";
		$cmd         = "CREATE TABLE bans (id INTEGER PRIMARY KEY, ban_time INTEGER, unban_time INTEGER, ip VARCHAR(15), guid INT(8), name VARCHAR(64));";
		$result_code = $bans_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $bans_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX bans_index ON bans (id,ban_time,unban_time,ip,guid,name)";
		$result_code = $bans_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $bans_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}

	# The definitions database
	$definitions_sth = $definitions_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$definitions_sth->execute
	  or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
	foreach ($definitions_sth->fetchrow_array) { $tables{$_} = $_; }

	if ($tables{'definitions'}) {
		print "definitions database brought online\n\n";
	}
	else {
		print "Creating definitions database...\n\n";
		$cmd         = "CREATE TABLE definitions (id INTEGER PRIMARY KEY, term VARCHAR(32), definition VARCHAR(250));";
		$result_code = $definitions_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX definitions_index ON definitions (id,term,definition)";
		$result_code = $definitions_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}

	# The stats database
	$stats_sth = $stats_dbh->prepare("SELECT name FROM SQLITE_MASTER");
	$stats_sth->execute
	  or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
	foreach ($stats_sth->fetchrow_array) { $tables{$_} = $_; }
	if ($tables{'stats'}) { print "stats database brought online\n\n"; }
	else {
		print "Creating stats database\n\n";
		$cmd         = "CREATE TABLE stats (id INTEGER PRIMARY KEY, guid INT(8), kills INTEGER, deaths INTEGER, headshots INTEGER, pistol_kills INTEGER, grenade_kills INTEGER, bash_kills INTEGER, shotgun_kills INTEGER, sniper_kills INTEGER, rifle_kills INTEGER, machinegun_kills INTEGER, best_killspree INTEGER, nice_shots INTEGER, bad_shots INTEGER, first_bloods INTEGER, bomb_plants INTEGER, bomb_defuses INTEGER );";
		$result_code = $stats_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code tables were created\n";
		}
		$cmd         = "CREATE INDEX stats_index ON stats (id,guid,kills,deaths,headshots,pistol_kills,grenade_kills,bash_kills,shotgun_kills,sniper_kills,rifle_kills,machinegun_kills,best_killspree,nice_shots,bad_shots,first_bloods,bomb_plants,bomb_defuses)";
		$result_code = $stats_dbh->do($cmd)
		  or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
		if (!$result_code) {
			print "ERROR: $result_code indexes were created\n";
		}
	}
}

# END: initialize_databases

# BEGIN: idle_check
sub idle_check {
	my $idle_for;
	print "Checking for idle players...\n";
	foreach $slot (keys %last_activity_by_slot) {
		if ($last_activity_by_slot{$slot} ne 'gone') {
			$idle_for = $time - $last_activity_by_slot{$slot};
			if ($idle_for > 120) {
				print "Slot $slot: $name_by_slot{$slot} has been idle for " . duration($idle_for) . "\n";
			}
			if (!defined($idle_warn_level{$slot})) {
				$idle_warn_level{$slot} = 0;
			}
			if (    ($idle_warn_level{$slot} < 1)
				and ($idle_for >= $config->{'antiidle_warn_level_1'}))
			{
				print "IDLE_WARN1: Idle Time for $name_by_slot{$slot} has exceeded warn1 threshold: " . duration($config->{'antiidle_warn_level_1'}) . "\n";
				&rcon_command("say $name_by_slot{$slot}^7 " . $config->{'antiidle_warn_message_1'} . " (idle for " . duration($idle_for) . ")");
				$idle_warn_level{$slot} = 1;
			}
			if (    ($idle_warn_level{$slot} < 2)
				and ($idle_for >= $config->{'antiidle_warn_level_2'}))
			{
				print "IDLE_WARN2: Idle Time for $name_by_slot{$slot} has exceeded warn2 threshold: " . duration($config->{'antiidle_warn_level_2'}) . "\n";
				&rcon_command("say $name_by_slot{$slot}^7 " . $config->{'antiidle_warn_message_2'} . " (idle for " . duration($idle_for) . ")");
				$idle_warn_level{$slot} = 2;
			}
			if ($idle_for >= $config->{'antiidle_kick_level'}) {
				print "KICK: Idle Time for $name_by_slot{$slot} exceeded.\n";
				&rcon_command("say $name_by_slot{$slot}^7 " . $config->{'antiidle_kick_message'});
				sleep 1;
				&rcon_command("clientkick $slot");
				&log_to_file('logs/kick.log', "IDLE: $name_by_slot{$slot} was kicked for being idle for too long " . duration($idle_for));
			}
		}
	}
}

# END: idle_check

# BEGIN: chat
sub chat {

	# Relevant Globals:
	#   $name
	#   $slot
	#   $message
	#   $guid
	my $chattype = shift;
	my $is_there;
	if ($name_by_slot{$slot} ne 'SLOT_EMPTY') { $name = $name_by_slot{$slot}; }
	if (!defined($ignore{$slot})) { $ignore{$slot} = 0; }

	# print the message to the console
	if ($config->{'show_talk'}) {
		print &strip_color("CHAT: $chattype: $name: $message\n");
	}
	&log_to_file('logs/chat.log', &strip_color("CHAT: $chattype: $name: $message"));

	# Anti-Spam functions
	if (($config->{'antispam'}) and (!$ignore{$slot})) {
		if (!defined($spam_last_said{$slot})) {
			$spam_last_said{$slot} = $message;
		}
		else {
			if ($spam_last_said{$slot} eq $message) {
				if (!defined($spam_count{$slot})) {
					$spam_count{$slot} = 1;
				}
				else { $spam_count{$slot} += 1; }
				if ($spam_count{$slot} == $config->{'antispam_warn_level_1'}) {
					&rcon_command("say $name_by_slot{$slot}^7: " . $config->{'antispam_warn_message_1'});
				}
				if ($spam_count{$slot} == $config->{'antispam_warn_level_2'}) {
					&rcon_command("say $name_by_slot{$slot}^7: " . $config->{'antispam_warn_message_2'});
				}
				if (    ($spam_count{$slot} >= $config->{'antispam_kick_level'})
					and ($spam_count{$slot} <= ($config->{'antispam_kick_level'} + 1)))
				{
					if (&flood_protection('anti-spam-kick', 30, $slot)) { }
					else {
						&rcon_command("say $name_by_slot{$slot}^7: " . $config->{'antispam_kick_message'});
						sleep 1;
						&rcon_command("clientkick $slot");
						&log_to_file('logs/kick.log', "SPAM: $name_by_slot{$slot} was kicked for spamming: $message");
					}
				}
				print "Spam: $name said $message repeated $spam_count{$slot} times\n";
			}
			else {
				$spam_last_said{$slot} = $message;
				$spam_count{$slot}     = 0;
			}
		}
	}

	# End Anti-Spam functions

	# populate the seen data
	$seen_sth = $seen_dbh->prepare("SELECT count(*) FROM seen WHERE name=?");
	$seen_sth->execute($name)
	  or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
	foreach ($seen_sth->fetchrow_array) { $is_there = $_; }

	if ($is_there) {
		$seen_sth = $seen_dbh->prepare("UPDATE seen SET time=?, saying=? WHERE name=?");
		$seen_sth->execute($time, $message, $name)
		  or &die_nice("Unable to do update\n");
	}
	else {
		$seen_sth = $seen_dbh->prepare("INSERT INTO seen VALUES (NULL, ?, ?, ?)");
		$seen_sth->execute($name, $time, $message)
		  or &die_nice("Unable to do insert\n");
	}

	# end of seen data population

	# Server Response / Penalty System
	if ($config->{'use_responses'}) {
		my $rule_name;
		my $penalty  = 0;
		my $response = 'undefined';
		my $index;

		# loop through all the rule_regex looking for matches
		foreach $rule_name (keys %rule_regex) {
			if ($message =~ /$rule_regex{$rule_name}/i) {

				# We have a match, initiate response.
				$index = $number_of_responses{$rule_name};
				if ($index) {
					$index    = int(rand($index)) + 1;
					$response = $rule_response->{$rule_name}->{$index};
					$penalty  = $rule_penalty{$rule_name};
					if ((!&flood_protection("chat-response-$rule_name", 30, $slot)) and (!$ignore{$slot}) and (!$kick_message_spam)) {
						&rcon_command("say $name^7: $response");
						print "Positive Match:\nRule Name: $rule_name\nPenalty: $penalty\nResponse: $response\n\n";
						&log_to_file('logs/response.log', "Rule: $rule_name Match Text: $message");
					}
				}
				if (!defined($penalty_points{$slot})) {
					$penalty_points{$slot} = $penalty;
				}
				elsif (!$ignore{$slot}) {
					$penalty_points{$slot} += $penalty;
					if ($penalty_points{$slot} > 100) { $penalty_points{$slot} = 100; }
					print "Penalty Points total for: $name: $penalty_points{$slot}\n";
				}
				if (    (!$ignore{$slot})
					and ($penalty_points{$slot} == 100)
					and (!$kick_message_spam))
				{
					&rcon_command("say $name^7: ^1I think we heard enough from you, get out of here!");
					sleep 1;
					&rcon_command("clientkick $slot");
					&log_to_file('logs/kick.log', "PENALTY: $name was kicked for exceeding their penalty points. Last Message: $message");
					$kick_message_spam = $time + 5;    # 5 seconds spam protection
				}
			}
		}
	}

	#  End of Server Response / Penalty System

	# Call Bad shot
	if (($config->{'bad_shots'}) and (!$ignore{$slot})) {
		if ($message =~ /^!?bs\W*$|^!?bad\s*shot\W*$|^!?bull\s*shit\W*$|^!?hacks?\W*$|^!?hacker\W*$|^!?hax\W*$|^that\s+was\s+(bs|badshot|bullshit)\W*$/i) {
			if (    (defined($last_killed_by_name{$slot}))
				and ($last_killed_by_name{$slot} ne 'none'))
			{
				if (   (&flood_protection('badshot', 30, $slot))
					or (&flood_protection('niceshot', 30, $slot)))
				{
				}
				elsif ($last_killed_by_guid{$slot}) {

					# update the Bad Shot counter.
					$stats_sth = $stats_dbh->prepare("UPDATE stats SET bad_shots = bad_shots + 1 WHERE guid=?");
					$stats_sth->execute($last_killed_by_guid{$slot})
					  or &die_nice("Unable to update stats\n");
					&rcon_command("say $name ^7called bad shot on $last_killed_by_name{$slot}");
				}
			}
		}
		elsif ($message =~ /^!?bs\W*$|^!?bad\s*shot\W*$|^!?bull\s*shit\W*$|^!?hacks?\W*$|^!?hacker\W*$|^!?hax\W*$|^that\s+was\s+(bs|badshot|bullshit)\s*(.*)/i) {
			my $search_string = $2;
			my @matches       = &matching_users($search_string);
			if (    ($#matches == 0)
				and (defined($last_kill_by_name{$matches[0]}))
				and ($last_kill_by_name{$matches[0]} ne 'none')
				and ($slot ne $matches[0]))
			{
				if (   (&flood_protection('badshot', 30, $slot))
					or (&flood_protection('niceshot', 30, $slot)))
				{
				}
				elsif ($last_kill_by_guid{$matches[0]}) {

					# update the Bad Shot counter.
					$stats_sth = $stats_dbh->prepare("UPDATE stats SET bad_shots = bad_shots + 1 WHERE guid=?");
					$stats_sth->execute($last_kill_by_guid{$matches[0]})
					  or &die_nice("Unable to update stats\n");
					&rcon_command("say $name ^7called bad shot on $name_by_slot{$matches[0]} ^7killing $last_kill_by_name{$matches[0]}");
				}
			}
		}
	}

	# End of Bad Shot

	# Call Nice Shot
	if (($config->{'nice_shots'}) and (!$ignore{$slot})) {
		if ($message =~ /\bnice\W?\s+(one|shot|1)\b|^n[1s]\W*$/i) {
			if (    (defined($last_killed_by_name{$slot}))
				and ($last_killed_by_name{$slot} ne 'none'))
			{
				if (   (&flood_protection('niceshot', 30, $slot))
					or (&flood_protection('badshot', 30, $slot)))
				{
				}
				elsif ($last_killed_by_guid{$slot}) {

					# update the Nice Shot counter.
					$stats_sth = $stats_dbh->prepare("UPDATE stats SET nice_shots = nice_shots + 1 WHERE guid=?");
					$stats_sth->execute($last_killed_by_guid{$slot})
					  or &die_nice("Unable to update stats\n");
					&rcon_command("say $name ^7called nice shot on $last_killed_by_name{$slot}");
				}
			}
		}
		elsif ($message =~ /\bnice\W?\s+(one|shot|1)\b|^n[1s]\s*(.*)/i) {
			my $search_string = $2;
			my @matches       = &matching_users($search_string);
			if (    ($#matches == 0)
				and (defined($last_kill_by_name{$matches[0]}))
				and ($last_kill_by_name{$matches[0]} ne 'none')
				and ($slot ne $matches[0]))
			{
				if (   (&flood_protection('niceshot', 30, $slot))
					or (&flood_protection('badshot', 30, $slot)))
				{
				}
				elsif ($last_kill_by_guid{$matches[0]}) {

					# update the Nice Shot counter.
					$stats_sth = $stats_dbh->prepare("UPDATE stats SET nice_shots = nice_shots + 1 WHERE guid=?");
					$stats_sth->execute($last_kill_by_guid{$matches[0]})
					  or &die_nice("Unable to update stats\n");
					&rcon_command("say $name ^7called nice shot on $name_by_slot{$matches[0]} ^7killing $last_kill_by_name{$matches[0]}");
				}
			}
		}
	}

	# End of Nice Shot

	# Auto-define questions (my most successful if statement evar?)
	if (   (!$ignore{$slot}) and ($message =~ /^(.*)\?$/)
		or ($message =~ /^!(.*)$/))
	{
		my $question = $1;
		my $counter  = 0;
		my @row;
		my @results;
		my $result;
		$definitions_sth = $definitions_dbh->prepare("SELECT definition FROM definitions WHERE term=?;");
		$definitions_sth->execute($question)
		  or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");

		while (@row = $definitions_sth->fetchrow_array) {
			print "DATABASE DEFINITION: $row[0]\n";
			push @results, "$name^7: ^1$question ^3is: ^2$row[0]";
		}
		if ($#results != -1) {
			if (&flood_protection('auto-define', 30, $slot)) { }
			else {
				foreach $result (@results) {
					&rcon_command("say $result");
					sleep 1;
				}
			}
		}
	}

	# Check for !commands
	if ((!$ignore{$slot}) and ($message =~ /^!/)) {

		# !locate (search_string)
		if ($message =~ /^!(geo)?locate\s+(.+)/i) {
			if (&check_access('locate')) { &locate($2); }
		}
		elsif ($message =~ /^!(geo)?locate\s*$/i) {
			if (&check_access('locate')) {
				if   (&flood_protection('locate-miss', 10, $slot)) { }
				else                                               { &rcon_command("say !locate who?"); }
			}
		}

		# !ignore (search_string)
		if ($message =~ /^!ignore\s+(.+)/i) {
			if (&check_access('ignore')) { &ignore($1); }
		}
		elsif ($message =~ /^!ignore\s*$/i) {
			if (&check_access('ignore')) {
				if   (&flood_protection('ignore-nomatch', 10, $slot)) { }
				else                                                  { &rcon_command("say !ignore who?"); }
			}
		}

		# !forgive (search_string)
		if ($message =~ /^!forgive\s+(.+)/i) {
			if (&check_access('forgive')) { &forgive($1); }
		}
		elsif ($message =~ /^!forgive\s*$/i) {
			if (&check_access('forgive')) {
				if   (&flood_protection('forgive-nomatch', 10, $slot)) { }
				else                                                   { &rcon_command("say !forgive who?"); }
			}
		}

		# !seen (search_string)
		elsif ($message =~ /^!seen\s+(.+)/i) {
			if (&check_access('seen')) { &seen($1); }
		}
		elsif ($message =~ /^!seen\s*$/i) {
			if (&check_access('seen')) {
				if   (&flood_protection('seen-nomatch', 10, $slot)) { }
				else                                                { &rcon_command("say !seen who?"); }
			}
		}

		# !kick (search_string)
		elsif ($message =~ /^!kick\s+(.+)/i) {
			if (&check_access('kick')) { &kick_command($1); }
		}
		elsif ($message =~ /^!kick\s*$/i) {
			if (&check_access('kick')) {
				&rcon_command("say !kick who?");
			}
		}

		# !tempban (search_string)
		elsif ($message =~ /^!tempban\s+(.+)\s+(\d+)/i) {
			if (&check_access('tempban')) { &tempban_command($1, $2); }
		}
		elsif ($message =~ /^!tempban\s+(.+)/i) {
			if (&check_access('tempban')) { &tempban_command($1); }
		}
		elsif ($message =~ /^!tempban\s*$/i) {
			if (&check_access('tempban')) {
				&rcon_command("say !tempban who?");
			}
		}

		# !ban (search_string)
		elsif ($message =~ /^!ban\s+(.+)/i) {
			if (&check_access('ban')) { &ban_command($1); }
		}
		elsif ($message =~ /^!ban\s*$/i) {
			if (&check_access('ban')) { &rcon_command("say !ban who?"); }
		}

		# !unban (search_string)
		elsif ($message =~ /^!unban\s+(.+)/i) {
			if (&check_access('ban')) { &unban_command($1); }
		}
		elsif ($message =~ /^!unban\s*$/i) {
			if (&check_access('ban')) {
				&rcon_command("say You can unban players by using their BAD ID's, check !lastbans to display recently banned players and their ID's");
			}
		}

		# !clearstats (search_string)
		elsif ($message =~ /^!clearstats\s+(.+)/i) {
			if (&check_access('clearstats')) { &clear_stats($1); }
		}
		elsif ($message =~ /^!clearstats\s*$/i) {
			if (&check_access('clearstats')) {
				&rcon_command("say !clearstats for who?");
			}
		}

		# !clearnames (search_string)
		elsif ($message =~ /^!clearnames\s+(.+)/i) {
			if (&check_access('clearnames')) { &clear_names($1); }
		}
		elsif ($message =~ /^!clearnames\s*$/i) {
			if (&check_access('clearnames')) {
				&rcon_command("say !clearnames for who?");
			}
		}

		# !ip (search_string)
		elsif ($message =~ /^!ip\s+(.+)/i) {
			if (&check_access('ip')) { &ip_player($slot, $1); }
		}
		elsif ($message =~ /^!ip\s*$/i) {
			if (&check_access('ip')) { &ip_player($slot); }
		}

		# !id (search_string)
		elsif ($message =~ /^!id\s+(.+)/i) {
			if (&check_access('id')) { &id_player($slot, $1); }
		}
		elsif ($message =~ /^!id\s*$/i) {
			if (&check_access('id')) { &id_player($slot); }
		}

		# !guid (search_string)
		elsif ($message =~ /^!guid\s+(.+)/i) {
			if (&check_access('guid')) { &guid_player($slot, $1); }
		}
		elsif ($message =~ /^!guid\s*$/i) {
			if (&check_access('guid')) { &guid_player($slot); }
		}

		# !age (search_string)
		elsif ($message =~ /^!age\s+(.+)/i) {
			if (&check_access('age')) { &age_player($slot, $1); }
		}
		elsif ($message =~ /^!age\s*$/i) {
			if (&check_access('age')) { &age_player($slot); }
		}

		# !name (search_string)
		elsif ($message =~ /^!name\s+(.+)/i) {
			if (&check_access('name')) { &name_player($slot, $1); }
		}
		elsif ($message =~ /^!name\s*$/i) {
			if (&check_access('name')) { &name_player($slot); }
		}

		# !rank (search_string)
		elsif ($message =~ /^!rank\s+(.+)/i) {
			if (&check_access('rank')) { &rank_player($slot, $1); }
		}
		elsif ($message =~ /^!rank\s*$/i) {
			if (&check_access('rank')) { &rank_player($slot); }
		}

		# !addname (name)
		elsif ($message =~ /^!addname\s+(.+)/i) {
			if (&check_access('addname')) { &add_name($1); }
		}
		elsif ($message =~ /^!addname\s*$/i) {
			if (&check_access('addname')) {
				&rcon_command("say !addname Name");
			}
		}

		# !addrank (rank)
		elsif ($message =~ /^!addrank\s+(.+)/i) {
			if (&check_access('addrank')) { &add_rank($1); }
		}
		elsif ($message =~ /^!addrank\s*$/i) {
			if (&check_access('addrank')) {
				&rcon_command("say !addrank Rank");
			}
		}

		# !clearname (name)
		elsif ($message =~ /^!clearname\s+(.+)/i) {
			if (&check_access('clearname')) { &clear_name($1); }
		}
		elsif ($message =~ /^!clearname\s*$/i) {
			if (&check_access('clearname')) {
				&rcon_command("say !clearname Name");
			}
		}

		# !clearrank (rank)
		elsif ($message =~ /^!clearrank\s+(.+)/i) {
			if (&check_access('clearrank')) { &clear_rank($1); }
		}
		elsif ($message =~ /^!clearrank\s*$/i) {
			if (&check_access('clearrank')) {
				&rcon_command("say !clearrank Rank");
			}
		}

		# !dbinfo (database)
		elsif ($message =~ /^!dbinfo\s+(.+)/i) {
			if (&check_access('dbinfo')) { &database_info($1); }
		}
		elsif ($message =~ /^!dbinfo\s*$/i) {
			if (&check_access('dbinfo')) {
				&rcon_command("say !dbinfo database");
			}
		}

		# !report (search_string)
		elsif ($message =~ /^!report\s+(.+)\s+=\s+(.+)/i) {
			if (&check_access('report')) { &report_player($1, $2); }
		}
		elsif ($message =~ /^!report\s*$/i) {
			if (&check_access('report')) {
				&rcon_command("say !report Player = Reason");
			}
		}

		# !define (word)
		elsif ($message =~ /^!(define|dictionary|dict)\s+(.+)/i) {
			if (&check_access('define')) {
				if   (&flood_protection('define', 30, $slot)) { }
				else                                          { &dictionary($2); }
			}
		}
		elsif ($message =~ /^!(define|dictionary|dict)\s*$/i) {
			if (&check_access('define')) {
				if (&flood_protection('dictionary-miss', 10, $slot)) { }
				else {
					&rcon_command("say $name^7: What do i need to add in a dictonary?");
				}
			}
		}

		# !undefine (word)
		elsif ($message =~ /^!undefine\s+(.+)/i) {
			if (&check_access('undefine')) {
				if (&flood_protection('undefine', 30, $slot)) { }
				else {
					my $undefine = $1;
					$definitions_sth = $definitions_dbh->prepare("SELECT count(*) FROM definitions WHERE term=?;");
					$definitions_sth->execute($undefine)
					  or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
					@row             = $definitions_sth->fetchrow_array;
					$definitions_sth = $definitions_dbh->prepare("DELETE FROM definitions WHERE term=?;");
					$definitions_sth->execute($undefine)
					  or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");

					if ($row[0] == 1) {
						&rcon_command("say ^2Removed one definition for: ^1$undefine");
					}
					elsif ($row[0] > 1) {
						&rcon_command("say ^2Removed ^3$row[0] ^2definitions for: ^1$undefine");
					}
					else {
						&rcon_command("say ^2No more definitions for: ^1$undefine");
					}
				}
			}
		}

		# !undef (word)
		elsif ($message =~ /^!undef\s+(.+)/i) {
			if (&check_access('undefine')) {
				if (&flood_protection('undef', 30, $slot)) { }
				else {
					my $undef = $1;
					$definitions_sth = $definitions_dbh->prepare("SELECT definition FROM definitions WHERE term=? ORDER BY id DESC LIMIT 1;");
					$definitions_sth->execute($undef)
					  or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
					@row = $definitions_sth->fetchrow_array;

					if ($row[0]) {
						$definitions_sth = $definitions_dbh->prepare("DELETE FROM definitions WHERE definition=?;");
						$definitions_sth->execute($row[0])
						  or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
						&rcon_command("say ^2Removed last definition for: ^1$undef");
					}
					else {
						&rcon_command("say ^2No more definitions for: ^1$undef");
					}
				}
			}
		}

		# !stats
		elsif ($message =~ /^!(xlr)?stats\s+(.+)/i) {
			if ((&check_access('stats')) and (&check_access('peek'))) {
				&stats($slot, $2);
			}
		}
		elsif ($message =~ /^!(xlr)?stats\s*$/i) {
			if (&check_access('stats')) { &stats($slot); }
		}

		# !lastkill
		elsif ($message =~ /^!last\s*kill\s+(.+)/i) {
			if (&check_access('lastkill')) { &lastkill($slot, $2); }
		}
		elsif ($message =~ /^!last\s*kill\s*$/i) {
			if (&check_access('lastkill')) { &lastkill($slot); }
		}

		# !lastkilled
		elsif ($message =~ /^!(last\s*killed|killedby|whokilledme|whowasthat)\s+(.+)/i) {
			if (&check_access('lastkilled')) { &lastkilled($slot, $2); }
		}
		elsif ($message =~ /^!(last\s*killed|killedby|whokilledme|whowasthat)\s*$/i) {
			if (&check_access('lastkilled')) { &lastkilled($slot); }
		}

		# !best
		elsif ($message =~ /^!best\b/i) {
			if (&check_access('best')) { &best; }
		}

		# !worst
		elsif ($message =~ /^!worst\b/i) {
			if (&check_access('worst')) { &worst; }
		}

		# !tdm
		elsif ($message =~ /^!tdm\b/i) {
			if (&check_access('map_control')) { &change_gametype('tdm'); }
		}

		# !ctf
		elsif ($message =~ /^!ctf\b/i) {
			if (&check_access('map_control')) { &change_gametype('ctf'); }
		}

		# !dm
		elsif ($message =~ /^!dm\b/i) {
			if (&check_access('map_control')) { &change_gametype('dm'); }
		}

		# !hq
		elsif ($message =~ /^!hq\b/i) {
			if (&check_access('map_control')) { &change_gametype('hq'); }
		}

		# !sd
		elsif ($message =~ /^!sd\b/i) {
			if (&check_access('map_control')) { &change_gametype('sd'); }
		}

		# !smoke
		elsif ($message =~ /^!(smokes?|smoke_grenades?|smoke_nades?)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("Smoke Grenades", $2);
			}
		}
		elsif ($message =~ /^!(smokes?|smoke_grenades?|smoke_nades?)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !grenades
		elsif ($message =~ /^!(nades?|grenades?|frag_grenades?|frag_nades?)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("Frag Grenades", $2);
			}
		}
		elsif ($message =~ /^!(nades?|grenades?|frag_grenades?|frag_nades?)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !shotguns
		elsif ($message =~ /^!(shotguns?|trenchguns?|shot_guns?|trench_guns?)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("Shotguns", $2);
			}
		}
		elsif ($message =~ /^!(shotguns?|trenchguns?|shot_guns?|trench_guns?)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !rifles
		elsif ($message =~ /^!(rifles?|bolt)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("Rifles", $2);
			}
		}
		elsif ($message =~ /^!(rifles?|bolt)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !semirifles
		elsif ($message =~ /^!(semirifles?)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("Semi-Rifles", $2);
			}
		}
		elsif ($message =~ /^!(semirifles?)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !snipers
		elsif ($message =~ /^!(snipers?|sniper_rifles?|sniper rifles?)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("Sniper Rifles", $2);
			}
		}
		elsif ($message =~ /^!(snipers?|sniper_rifles?|sniper rifles?)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !mgs
		elsif ($message =~ /^!(mgs?|machineguns?|machine_guns?)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("MachineGuns", $2);
			}
		}
		elsif ($message =~ /^!(mgs?|machineguns?|machine_guns?)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !smgs
		elsif ($message =~ /^!(smgs?|submachineguns?|submachine_guns?)\s+(.+)/i) {
			if (&check_access('weapon_control')) {
				&toggle_weapon("SubMachineGuns", $2);
			}
		}
		elsif ($message =~ /^!(smgs?|submachineguns?|submachine_guns?)\s*$/i) {
			if (&check_access('weapon_control')) {
				&rcon_command("say $name^7: You can turn ^1!$1 on ^7or turn ^1!$1 off");
			}
		}

		# !say
		elsif ($message =~ /^!say\s+(.+)/i) {
			if (&flood_protection('say', 30, $slot)) { }
			elsif (&check_access('say')) { &rcon_command("say $1"); }
		}

		# !broadcast
		elsif ($message =~ /^!broadcast\s+(.+)/i) {
			if (&check_access('broadcast')) { &broadcast_message($1); }
		}

		# !tell
		elsif ($message =~ /^!tell\s+([^\s]+)\s+(.*)/i) {
			if (&check_access('tell')) { &tell($1, $2); }
		}

		# !hostname
		elsif ($message =~ /^!(host\s?name|server\s?name)\s+(.+)/i) {
			if (&check_access('hostname')) {
				if (&flood_protection('hostname', 30, $slot)) { }
				else {
					$server_name = $2;
					&rcon_command("sv_hostname $server_name");
					&rcon_command("say Changing sever name...");
					sleep 1;
					&rcon_command("say ^2OK^7. Server name changed to: $server_name");
				}
			}
		}
		elsif ($message =~ /^!(host\s?name|server\s?name)\s*$/i) {
			if (&check_access('hostname')) {
				if (&flood_protection('hostname', 30, $slot)) { }
				else {
					$temporary = &rcon_query("sv_hostname");
					if ($temporary =~ /\"sv_hostname\" is: \"([^\"]+)\^7\"/m) {
						$server_name = $1;
						if ($server_name =~ /./) {
							&rcon_command("say Server name is currently is $server_name^7, use !hostname to change it");
						}
					}
				}
			}
		}

		# !reset
		elsif ($message =~ /^!reset/i) {
			if (&check_access('reset')) {
				&rcon_command("say Ok $name^7, resetting values...");
				&reset;
			}
		}

		# !reboot
		elsif ($message =~ /^!reboot/i) {
			if (&check_access('reboot')) {
				&rcon_command("say Ok $name^7, rebooting myself...");
				exec "perl $0";
			}
		}

		# !reconfig
		elsif ($message =~ /^!reconfig/i) {
			if (&check_access('reconfig')) {
				&rcon_command("say Ok $name^7, reloading config file...");
				&load_config_file($config_name);
			}
		}

		# !version
		elsif ($message =~ /^!ver(sion)?\b/i) {
			if (&check_access('version')) {
				if (&flood_protection('version', 30)) { }
				else {
					&rcon_command("say Nanny^7 for CoD2 version^2 $version ($modtime)");
					sleep 1;
					&rcon_command("say ^7by ^4smugllama ^7/ ^1indie cypherable ^7/ Dick Cheney");
					sleep 1;
					&rcon_command("say with additional help from: Bulli, Badrobot, and Grisu Drache - thanks!");
					sleep 1;
					&rcon_command("say ^3Downloadable at: ^2http://smaert.com/nannybot.zip");
					sleep 1;
					&rcon_command("say Additional work - ^5V^0oro^5N");
					sleep 1;
					&rcon_command("say ^3Source code for the latest version can be found at: ^2https://github.com/voron00/Nanny");
				}
			}
		}

		# !nextmap (not to be confused with !rotate)
		elsif ($message =~ /^!next([s_])?(map|level)?\b/i) {
			if (&check_access('nextmap')) {
				if (&flood_protection('nextmap', 30, $slot)) { }
				elsif ($next_map and $next_gametype) {
					&rcon_command("say $name^7: Next map will be: ^2" . &description($next_map) . " ^7(^3" . &description($next_gametype) . "^7)");
				}
			}
		}

		# !map
		elsif ($message =~ /^!map\s+(\w+)\b/i) {
			if (&check_access('map')) {
				if (&flood_protection('map', 30, $slot)) { }
				else {
					&change_map($1);
				}
			}
		}
		elsif ($message =~ /^!map\s*$/i) {
			if (&check_access('map')) {
				&rcon_command("say !map mapname");
			}
		}

		# !rotate
		elsif ($message =~ /^!rotate\b/i) {
			if (&check_access('map_control')) {
				if ($next_map and $next_gametype) {
					&rcon_command("say ^2Changing map^7...");
					sleep 1;
					&rcon_command("map_rotate");
				}
			}
		}

		# !restart
		elsif ($message =~ /^!restart\b/i) {
			if (&check_access('map_control')) {
				&rcon_command("say ^2Restarting map^7...");
				sleep 1;
				&rcon_command("map_restart");
			}
		}

		# !fastrestart
		elsif ($message =~ /^!(quick|fast)\s?restart\b/i) {
			if (&check_access('map_control')) {
				&rcon_command("say ^2Fast-Restarting^7...");
				sleep 1;
				&rcon_command("fast_restart");
			}
		}

		# !voting
		elsif ($message =~ /^!(voting|vote|allowvote|allowvoting)\s+(.+)/i) {
			if (&check_access('voting')) { &voting_command($2); }
		}
		elsif ($message =~ /^!(voting|vote|allowvote|allowvoting)\s*$/i) {
			if (&check_access('voting')) {
				&rcon_command("say !voting on or !voting off ?");
			}
		}

		# !voice
		elsif ($message =~ /^!(voice|voicechat|sv_voice)\s+(.+)/i) {
			if (&check_access('voice')) { &voice_command($2); }
		}
		elsif ($message =~ /^!(voice|voicechat|sv_voice)\s*$/i) {
			if (&check_access('voice')) {
				&rcon_command("say !voice on or !voice off ?");
			}
		}

		# !antilag
		elsif ($message =~ /^!(g_)?antilag\s+(.+)/i) {
			if (&check_access('antilag')) { &antilag_command($2); }
		}
		elsif ($message =~ /^!(g_)?antilag\s*$/i) {
			if (&check_access('antilag')) {
				&rcon_command("say !antilag on or !antilag off ?");
			}
		}

		# !vote (kick, ban, map, type)
		elsif ($message =~ /^!vote(kick|ban|map|type)\s+(.+)/i) {
			if (&flood_protection('vote-spam', 10, $slot)) { }
			elsif ($vote_started) { }
			elsif ((&check_access('vote_kick') and ($1 eq 'kick'))) {
				&vote($name, $1, $2);
			}
			elsif ((&check_access('vote_ban') and ($1 eq 'ban'))) {
				&vote($name, $1, $2);
			}
			elsif ((&check_access('vote_map') and ($1 eq 'map'))) {
				&vote($name, $1, $2);
			}
			elsif ((&check_access('vote_type') and ($1 eq 'type'))) {
				&vote($name, $1, $2);
			}
		}
		elsif ($message =~ /^!vote(kick|ban|map|type)\s*$/i) {
			if (&flood_protection('vote-nomatch', 10, $slot)) { }
			elsif ($vote_started) { }
			elsif ((&check_access('vote_kick') and ($1 eq 'kick'))) {
				&rcon_command("say !vote$1 who?");
			}
			elsif ((&check_access('vote_ban') and ($1 eq 'ban'))) {
				&rcon_command("say !vote$1 who?");
			}
			elsif ((&check_access('vote_map') and ($1 eq 'map'))) {
				&rcon_command("say !vote$1 which map?");
			}
			elsif ((&check_access('vote_type') and ($1 eq 'type'))) {
				&rcon_command("say !vote$1 which gametype?");
			}
		}

		# !voteyes
		elsif ($message =~ /^!(vote)?yes\s*$/i) {
			if (&check_access('vote')) { &yes($slot, $name); }
		}

		# !voteno
		elsif ($message =~ /^!(vote)?no\s*$/i) {
			if (&check_access('vote')) { &no($slot, $name); }
		}

		# !votestatus
		elsif ($message =~ /^!votestatus\s*$/i) {
			if (&check_access('vote_status')) {
				if ($vote_started) {
					&rcon_command("say Vote: $vote_string " . &description($vote_target) . "^7: Time Remaining: ^4" . ($vote_time - $time) . " ^7seconds: Voted ^2YES^7: ^2$voted_yes^7, Voted ^1NO^7: ^1$voted_no");
				}
				else {
					&rcon_command("say There is no active vote at this time.");
				}
			}
		}

		# !endvote
		elsif ($message =~ /^!endvote\s*$/i) {
			if (&check_access('vote_end')) {
				if ($vote_started) { $vote_time = $time; }
				else {
					&rcon_command("say There is no active vote at this time.");
				}
			}
		}

		# !playerscount
		elsif ($message =~ /^!playerscount\s*$/i) {
			if (&check_access('players_count')) {
				&rcon_command("say Active players count - ^3$players_count");
			}
		}

		# !killcam
		elsif ($message =~ /^!killcam\s+(.+)/i) {
			if (&check_access('killcam')) { &killcam_command($1); }
		}
		elsif ($message =~ /^!killcam\s*$/i) {
			if (&check_access('killcam')) {
				&rcon_command("say !killcam on or !killcam off ?");
			}
		}

		# !forcerespawn
		elsif ($message =~ /^!forcerespawn\s+(.+)/i) {
			if (&check_access('forcerespawn')) {
				&forcerespawn_command($1);
			}
		}
		elsif ($message =~ /^!forcerespawn\s*$/i) {
			if (&check_access('forcerespawn')) {
				&rcon_command("say !forcerespawn on or !forcerespawn off ?");
			}
		}

		# !teambalance
		elsif ($message =~ /^!teambalance\s+(.+)/i) {
			if (&check_access('teambalance')) {
				&teambalance_command($1);
			}
		}
		elsif ($message =~ /^!teambalance\s*$/i) {
			if (&check_access('teambalance')) {
				&rcon_command("say !teambalance on or !teambalance off ?");
			}
		}

		# !spectatefree
		elsif ($message =~ /^!spectatefree\s+(.+)/i) {
			if (&check_access('spectatefree')) {
				&spectatefree_command($1);
			}
		}
		elsif ($message =~ /^!spectatefree\s*$/i) {
			if (&check_access('spectatefree')) {
				&rcon_command("say !spectatefree on or !spectatefree off ?");
			}
		}

		# !friendlyfire
		elsif (($message =~ /^!fr[ie]{1,2}ndly.?fire\s+(.+)/i)
			or ($message =~ /^!team[ _\-]?kill\s+(.+)/i))
		{
			if (&check_access('friendlyfire')) {
				&friendlyfire_command($1);
			}
		}
		elsif (($message =~ /^!fr[ie]{1,2}ndly.?fire\s*$/i)
			or ($message =~ /^!team[ _\-]?kill\s*$/i))
		{
			if (&check_access('friendlyfire')) {
				&rcon_command("say $name^7: You can ^1!friendlyfire ^50 ^7to turn OFF friendly fire");
				sleep 1;
				&rcon_command("say $name^7: You can ^1!friendlyfire ^51 ^7to turn ON friendly fire");
				sleep 1;
				&rcon_command("say $name^7: You can ^1!friendlyfire ^52 ^7to turn ON friendly fire with reflect damage");
				sleep 1;
				&rcon_command("say $name^7: You can ^1!friendlyfire ^53 ^7to turn ON friendly fire with shared damage");
				sleep 1;
				my $state_string = 'unknown';

				if ($friendly_fire == 0) {
					$state_string = "Friendly fire is currently OFF";
				}
				elsif ($friendly_fire == 1) {
					$state_string = "Friendly fire is currently ON";
				}
				elsif ($friendly_fire == 2) {
					$state_string = "Friendly fire is currently REFLECT DAMAGE";
				}
				elsif ($friendly_fire == 3) {
					$state_string = "Friendly fire is currently SHARED DAMAGE";
				}
				if ($state_string ne 'unknown') {
					&rcon_command("say $name^7: $state_string");
				}
			}
		}

		# !glitch
		elsif ($message =~ /^!glitch\s+(.+)/i) {
			if (&check_access('glitch')) { &glitch_command($1); }
		}
		elsif ($message =~ /^!glitch\s*$/i) {
			if (&check_access('glitch')) {
				&rcon_command("say !glitch on or !glitch off ?");
			}
		}

		# !names (search_string)
		elsif ($message =~ /^!names\s+(.+)/i) {
			if (&check_access('names')) { &names($1); }
		}
		elsif ($message =~ /^!(names)\s*$/i) {
			if (&check_access('names')) {
				&rcon_command("say !names for who?");
			}
		}

		# !uptime
		elsif ($message =~ /^!uptime\b/i) {
			if (&check_access('uptime')) {
				if (&flood_protection('uptime', 30, $slot)) { }
				elsif ($uptime =~ /(\d+):(\d+)/) {
					&rcon_command("say This server is up and running already " . &duration(($1 * 60) + $2));
				}
			}
		}

		# !help
		elsif ($message =~ /^!help/i) {
			if (&flood_protection('help', 120)) { }
			else {
				if (&check_access('stats')) {
					&rcon_command("say $name^7: You can use ^1!stats ^7to display your detailed statistic on this server");
					sleep 1;
				}
				if (&check_access('seen')) {
					&rcon_command("say $name^7: You can use ^1!seen ^5player ^7to display when this player was on server and what he we said last time");
					sleep 1;
				}
				if (&check_access('locate')) {
					&rcon_command("say $name^7: You can ^1!locate ^5player ^7to display his approximate location in a real world");
					sleep 1;
				}
				if (&check_access('lastkill')) {
					&rcon_command("say $name^7: You can use ^1!lastkill ^7to display who did you killed for the last time");
					sleep 1;
				}
				if (&check_access('lastkilled')) {
					&rcon_command("say $name^7: You can use ^1!lastkilled ^7to display who killed you for the last time");
					sleep 1;
				}
				if (&check_access('map_control')) {
					&rcon_command("say $name^7: You can change gametype with: ^1!dm !tdm !ctf !sd !hq");
					sleep 1;
					&rcon_command("say $name^7: You can: ^1!restart ^7map or ^1!rotate ^7to change to next map");
					sleep 1;
					&rcon_command("say $name^7: Or: ^1!beltot !brecourt !burgundy !caen !carentan !el-alamein !moscow !leningrad !matmata !st.mereeglise !stalingrad !toujane !villers");
					sleep 1;
				}
				if (&check_access('kick')) {
					&rcon_command("say $name^7: You can ^1!kick ^5player ^7to kick him from the server");
					sleep 1;
				}
				if (&check_access('tempban')) {
					&rcon_command("say $name^7: You can ^1!tempban ^5player ^7to temporarily bad player");
					sleep 1;
				}
				if (&check_access('ban')) {
					&rcon_command("say $name^7: You can ^1!ban ^5player ^7to permanently ban player");
					sleep 1;
					&rcon_command("say $name^7: You can ^1!unban ^5player ^7or ^1!unban ^5BAN ID# ^7to remove ban");
					sleep 1;
					&rcon_command("say $name^7: You can use ^1!lastbans ^5number ^7to display recently banned players");
					sleep 1;
				}
				if (&check_access('voting')) {
					&rcon_command("say $name^7: You can turn ^1!voting ^5on ^7or turn ^1!voting ^5off");
					sleep 1;
				}
				if (&check_access('killcam')) {
					&rcon_command("say $name^7: You can turn ^1!killcam ^5on ^7or turn ^1!killcam ^5off");
					sleep 1;
				}
				if (&check_access('teamkill')) {
					&rcon_command("say $name^7: You can ^1!friendlyfire ^5[0-4] ^7to set friendly fire mode");
					sleep 1;
				}
				if (&check_access('fly')) {
					&rcon_command("say $name^7: Yo can ^1!fly ^7to turn off gravity for 20 seconds");
					sleep 1;
				}
				if (&check_access('gravity')) {
					&rcon_command("say $name^7: You can ^1!gravity ^5number ^7to set g_gravity mode");
					sleep 1;
				}
				if (&check_access('speed')) {
					&rcon_command("say $name^7: You can ^1!speed ^5number ^7to set g_speed mode");
					sleep 1;
				}
				if (&check_access('glitch')) {
					&rcon_command("say $name^7: You can turn ^1!glitch ^5on ^7or turn ^1!glitch ^5off ^7to set Glitch Server Mode");
					sleep 1;
				}
				if (&check_access('names')) {
					&rcon_command("say $name^7: You can ^1!names ^5player ^7to display nicknames this player also used");
					sleep 1;
				}
				if (&check_access('best')) {
					&rcon_command("say $name^7: You can use ^1!best ^7to display list of best players on server");
					sleep 1;
				}
				if (&check_access('worst')) {
					&rcon_command("say $name^7: You can use ^1!worst ^7to display list of worst players on server");
					sleep 1;
				}
				if (&check_access('uptime')) {
					&rcon_command("say $name^7: You can use ^1!uptime ^7to display for how long this server is already running");
					sleep 1;
				}
				if (&check_access('define')) {
					&rcon_command("say $name^7: You can use ^1!define ^5word ^7to add it in a dictonary");
					sleep 1;
				}
				if (&check_access('version')) {
					&rcon_command("say $name^7: You can use ^1!version ^7to display current version of the program and it's authors");
					sleep 1;
				}
				if (&check_access('reset')) {
					&rcon_command("say $name^7: You can use ^1!reset ^7to reset current known values");
					sleep 1;
				}
				if (&check_access('reboot')) {
					&rcon_command("say $name^7: You can use ^1!reboot ^7to reboot the program");
					sleep 1;
				}
				if (&check_access('reconfig')) {
					&rcon_command("say $name^7: You can use ^1!reconfig ^7to reload a configuration file");
					sleep 1;
				}
				if (&check_access('ignore')) {
					&rcon_command("say $name^7: You can ^1!ignore ^5player^7 to prevent me from listening of what he said");
					sleep 1;
				}
				if (&check_access('broadcast')) {
					&rcon_command("say $name^7: You can ^1!broadcast ^5message ^7to send it to other your remote servers");
					sleep 1;
				}
				if (&check_access('hostname')) {
					&rcon_command("say $name^7: You can ^1!hostname ^5Name ^7to rename the server");
					sleep 1;
				}
				if (&check_access('forgive')) {
					&rcon_command("say $name^7: You can ^1!forgive ^5player ^7to forgive his dirty deeds");
					sleep 1;
				}
				if (&check_access('vote_kick')) {
					&rcon_command("say $name^7: You can use ^1!votekick ^5player ^7to initiate a vote to kick this player");
					sleep 1;
				}
				if (&check_access('vote_ban')) {
					&rcon_command("say $name^7: You can use ^1!voteban ^5player ^7to initiate a vote to ban this player");
					sleep 1;
				}
				if (&check_access('vote_map')) {
					&rcon_command("say $name^7: You can use ^1!votemap ^5map ^7to initiate a vote for the map change");
					sleep 1;
				}
				if (&check_access('vote_type')) {
					&rcon_command("say $name^7: You can use ^1!votetype ^5gametype ^7to initiate a vote for the gametype change");
					sleep 1;
				}
				if (&check_access('report')) {
					&rcon_command("say $name^7: You can use ^1!report ^5player ^7= ^2reason ^7to report this player");
					sleep 1;
				}
			}
		}

		# !fly
		elsif ($message =~ /^!fly\b/i) {
			if (&check_access('fly')) {
				if (&flood_protection('fly', 30, $slot)) { }
				else {
					&rcon_command("say Like a birds in the sky you shall FLY!!!");
					&rcon_command("g_gravity 10");
					$fly_timer = $time + 20;
				}
			}
		}

		# !gravity (number)
		if ($message =~ /^!(g_)?gravity\s*(.*)/i) {
			if (&check_access('gravity')) { &gravity_command($2); }
		}

		# !calc (expression)
		if ($message =~ /^!(calculater?|calc|calculator)\s+(.+)/i) {
			if (&flood_protection('calculator', 30, $slot)) { }
			elsif ($2 =~ /[^\d\.\+\-\/\*\s+\(\)]/) { }
			elsif (defined(eval($2))) {
				&rcon_command("say ^2$2 ^7=^1 " . eval($2));
			}
		}

		# !sin (value)
		if ($message =~ /^!sin\s+(\d+)/i) {
			if   (&flood_protection('trigonometry-sin', 30, $slot)) { }
			else                                                    { &rcon_command("say ^2sin $1 ^7=^1 " . sin($1)); }
		}

		# !cos (value)
		if ($message =~ /^!cos\s+(\d+)/i) {
			if   (&flood_protection('trigonometry-cos', 30, $slot)) { }
			else                                                    { &rcon_command("say ^2cos $1 ^7=^1 " . cos($1)); }
		}

		# !tan (value)
		if ($message =~ /^!tan\s+(\d+)/i) {
			if   (&flood_protection('trigonometry-tan', 30, $slot)) { }
			else                                                    { &rcon_command("say ^2tan $1 ^7=^1 " . &tan($1)); }
		}

		# !perl -v
		if ($message =~ /^!perl\s+-v\b/i) {
			if   (&flood_protection('perl-version', 30, $slot)) { }
			else                                                { &rcon_command("say Perl Version: ^3$^V"); }
		}

		# !osinfo
		if ($message =~ /^!os(info|name)\b/i) {
			if   (&flood_protection('os-version', 30, $slot)) { }
			else                                              { &rcon_command("say OS Version: ^3$^O"); }
		}

		# !speed (number)
		if ($message =~ /^!(g_)?speed\s*(.*)/i) {
			if (&check_access('speed')) { &speed_command($2); }
		}

		# !nuke
		if ($message =~ /^!(big\s+red\s+button|nuke)/i) {
			if (&check_access('nuke')) { &nuke; }
		}

		# !announce
		if ($message =~ /^!announce/i) {
			if (&check_access('announce')) { &make_announcement; }
		}

		# !affiliate
		if ($message =~ /^!affiliate/i) {
			if (&check_access('affiliate')) {
				&make_affiliate_server_announcement;
			}
		}

		# !sanity
		if ($message =~ /^!sanity/i) {
			if (&check_access('sanity')) {
				&guid_sanity_check($guid_by_slot{$slot}, $ip_by_slot{$slot});
			}
		}

		# !audit
		if ($message =~ /^!audit/i) {
			if (&check_access('audit')) { &check_guid_zero_players; }
		}

		# Map Commands
		# !beltot or !farmhouse
		elsif ($message =~ /^!beltot\b|!farmhouse\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_farmhouse');
			}
		}

		# !villers !breakout !vb !bocage !villers-bocage
		elsif ($message =~ /^!villers\b|^!breakout\b|^!vb\b|^!bocage\b|^!villers-bocage\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_breakout');
			}
		}

		# !brecourt
		elsif ($message =~ /^!brecourt\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_brecourt');
			}
		}

		# !burgundy  (frequently misspelled, loose matching on vowels)
		elsif ($message =~ /^!b[ieu]rg[aeiou]?ndy\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_burgundy');
			}
		}

		# !carentan  (frequently misspelled, loose matching on vowels)
		elsif ($message =~ /^!car[ie]nt[ao]n\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_carentan');
			}
		}

		# !st.mere !dawnville !eglise !st.mereeglise
		elsif ($message =~ /^!(st\.?mere|dawnville|egli[sc]e|st\.?mere.?egli[sc]e)\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_dawnville');
			}
		}

		# !el-alamein !egypt !decoy
		elsif ($message =~ /^!(el.?alamein|egypt|decoy)\b/i) {
			if (&check_access('map_control')) { &change_map('mp_decoy'); }
		}

		# !moscow !downtown
		elsif ($message =~ /^!(moscow|downtown)\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_downtown');
			}
		}

		# !leningrad      (commonly misspelled, loose matching)
		elsif ($message =~ /^!len+[aeio]ngrad\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_leningrad');
			}
		}

		# !matmata
		elsif ($message =~ /^!matmata\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_matmata');
			}
		}

		# !stalingrad !railyard
		elsif ($message =~ /^!(st[ao]l[ie]ngrad|railyard)\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_railyard');
			}
		}

		# !toujane
		elsif ($message =~ /^!toujane\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_toujane');
			}
		}

		# !caen  !trainstation
		elsif ($message =~ /^!(caen|train.?station)\b/i) {
			if (&check_access('map_control')) {
				&change_map('mp_trainstation');
			}
		}

		# !rostov  !harbor
		elsif ( ($message =~ /^!(harbor|rostov)\b/i)
			and ($cod_version ne '1.0'))
		{
			if (&check_access('map_control')) {
				&change_map('mp_harbor');
			}
		}

		# !rhine  !wallendar
		elsif ( ($message =~ /^!(rhine|wallendar)\b/i)
			and ($cod_version ne '1.0'))
		{
			if (&check_access('map_control')) { &change_map('mp_rhine'); }
		}

		# End of Map Commands
		# !time
		elsif ($message =~ /^!time\b/i) {
			if (&check_access('time')) {
				if (&flood_protection('time', 30, $slot)) { }
				else {
					&rcon_command("say Current time: ^2$currenttime ^7| ^3$currentdate");
				}
			}
		}

		# !ragequit
		elsif ($message =~ /^!(rage(quit)?|rq)\b/i) {
			if (&flood_protection('rage', 30, $slot)) { }
			else {
				&rcon_command("say $name ^7said: Screw you guys, i'm going home, and left the game");
				sleep 1;
				&rcon_command("clientkick $slot");
			}
		}

		# !lastbans
		elsif ($message =~ /^!(lastbans?|recentbans?|bans|banned)\s+(\d+)/i) {
			if (&check_access('lastbans')) { &last_bans($2); }
		}
		elsif ($message =~ /^!(lastbans?|recentbans?|bans|banned)/i) {
			if (&check_access('lastbans')) { &last_bans(5); }
		}
	}
}

# END of !commands
# END: chat

# BEGIN: strip_color($string)
sub strip_color {
	my $string = shift;
	$string =~ s/\^\d//g;
	return $string;
}

# END: strip_color

# BEGIN: strip_space($string)
sub strip_space {
	my $string = shift;
	$string =~ s/\s//g;
	return $string;
}

# END: strip_space

# BEGIN: description($string)
sub description {
	my $string = shift;
	if (defined($description{$string})) {
		return $description{$string};
	}
	else { return $string; }
}

# END: strip_color

# BEGIN: locate($search_string)
sub locate {
	my $search_string = shift;
	my $location;
	my @matches = &matching_users($search_string);
	my $guessed;
	my $spoof_match;

	if (    ($#matches == -1)
		and ($search_string !~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/)
		and ($search_string !~ /^console|nanny|server\b/i))
	{
		if (&flood_protection('locate-nomatch', 10, $slot)) { return 1; }
		&rcon_command("say No matches for: $search_string");
	}
	else {
		if (    ($search_string =~ /^\.$|^\*$|^all$|^.$/i)
			and (&flood_protection('locate-all', 120)))
		{
			return 1;
		}
		if (&flood_protection('locate', 30, $slot)) { return 1; }
		foreach $slot (@matches) {
			if ($ip_by_slot{$slot}) {
				print "MATCH: " . $name_by_slot{$slot} . ", IP = $ip_by_slot{$slot}\n";
				$ip = $ip_by_slot{$slot};
				if ($ip =~ /\?$/) {
					$guessed = 1;
					$ip =~ s/\?$//;
				}
				if ($ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/) {
					$location = &geolocate_ip($ip);
					if ($guessed) {
						$location = $name_by_slot{$slot} . " ^7proably has joined us from ^2" . $location;
					}
					else {
						$location = $name_by_slot{$slot} . " ^7has joined us from ^2" . $location;
					}

					# location spoofing
					foreach $spoof_match (keys(%location_spoof)) {
						if (&strip_color($name_by_slot{$slot}) =~ /$spoof_match/i) {
							$location = $name_by_slot{$slot} . " ^7" . $location_spoof{$spoof_match};
						}
					}
					&rcon_command("say $location");
					sleep 1;
				}
			}
		}
	}
	if ($search_string =~ /^console|nanny|server\b/i) {
		$location = &geolocate_ip($config->{'ip'});
		$location = "This server are located in ^2" . $location;
		&rcon_command("say $location");
		sleep 1;
	}
	elsif ($search_string =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/) {
		$location = &geolocate_ip($1);
		$location = "^3$1 ^7located in ^2" . $location;
		&rcon_command("say $location");
		sleep 1;
	}
}

# END: locate

# BEGIN: status
sub status {
	my $status = &rcon_query('status');
	print "$status\n";
	my @lines = split(/\n/, $status);
	$players_count = 0;

	foreach (@lines) {
		if (/^map:\s+(\w+)$/) { $mapname = $1; }
		if (/^[\sX]+(\d+)\s+(-?\d+)\s+([\dCNT]+)\s+(\d+)\s+(.*)\^7\s+(\d+)\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):([\d\-]+)\s+([\d\-]+)\s+(\d+)$/) {
			($slot, $score, $ping, $guid, $name, $lastmsg, $ip, $port, $qport, $rate) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);

			# strip trailing spaces.
			$name =~ s/\s+$//;

			# cache ping
			$ping_by_slot{$slot} = $ping;

			# update name by slot
			if (length($name) < 32) {
				&update_name_by_slot($name, $slot);
			}

			# cache the guid
			$guid_by_slot{$slot} = $guid;

			# cache slot to IP mappings
			$ip_by_slot{$slot} = $ip;

			# cache the ip_to_guid mapping
			if (($ip) and ($guid)) { &cache_ip_to_guid($ip, $guid); }

			# cache the guid_to_name mapping
			if (($guid) and ($name) and (length($name) < 32)) {
				&cache_guid_to_name($guid, $name);
			}

			# cache the ip_to_name mapping
			if (($ip) and ($name) and (length($name) < 32)) {
				&cache_ip_to_name($ip, $name);
			}

			# GUID Sanity Checking - detects when the server is not tracking GUIDs correctly.
			if ($guid) {

				# we know the GUID is non-zero.  Is it the one we most recently saw join?
				if (    ($guid == $most_recent_guid)
					and ($slot == $most_recent_slot))
				{
					# was it recent enough to still be cached by activision?
					if (($time - $most_recent_time) < (2 * $rconstatus_interval)) {

						# Is it time to run another sanity check?
						if (($time - $last_guid_sanity_check) > ($guid_sanity_check_interval)) {
							&guid_sanity_check($guid, $ip);
						}
					}
				}
			}

			# Ping-related checks. (Known Bug:  Not all slots are ping-enforced, rcon can't always see all the slots.)
			if ($ping ne 'CNCT') {
				if ($ping == 999) {
					if (!defined($last_ping_by_slot{$slot})) {
						$last_ping_by_slot{$slot} = 0;
					}
					if (    ($last_ping_by_slot{$slot} == 999)
						and ($config->{'ping_enforcement'})
						and ($config->{'999_quick_kick'}))
					{
						print "PING ENFORCEMENT: 999 ping for $name_by_slot{$slot}\n";
						&rcon_command("say $name_by_slot{$slot} ^7was kicked for having a 999 ping");
						sleep 1;
						&rcon_command("clientkick $slot");
						&log_to_file('logs/kick.log', "PING: $name_by_slot{$slot} was kicked for having a 999 ping for too long");
					}
				}
				elsif ($ping > $config->{'max_ping'}) {
					if (!defined($last_ping_by_slot{$slot})) {
						$last_ping_by_slot{$slot} = 0;
					}
					if ($last_ping_by_slot{$slot} > ($config->{'max_ping'})
						and ($config->{'ping_enforcement'}))
					{
						print "PING ENFORCEMENT: too high ping for $name_by_slot{$slot}\n";
						&rcon_command("say $name_by_slot{$slot} ^7was kicked for having a too high ping ($ping_by_slot{$slot} | $config->{'max_ping'})");
						sleep 1;
						&rcon_command("clientkick $slot");
						&log_to_file('logs/kick.log', "$name_by_slot{$slot} was kicked for having too high ping ($ping_by_slot{$slot} | $config->{'max_ping'})");
					}
				}
				else {
					# update players count, count only active players
					$players_count++;

					# Check for banned IP
					if ($ip) { &banned_ip_check($slot); }

					# Since we have spam protection anyway, we can add this
					if ($guid) { &banned_guid_check($slot); }
				}

				# we need to remember this for the next ping we check.
				$last_ping_by_slot{$slot} = $ping;
			}

			# End of Ping Checks.
		}
	}

	# BEGIN: IP Guessing - if we have players who we don't get IP's with status, try to fake it.
	foreach $slot (sort { $a <=> $b } keys %ip_by_slot) {
		if ($guid_by_slot{$slot}) {
			$sth = $ip_to_guid_dbh->prepare("SELECT ip FROM ip_to_guid WHERE guid=? ORDER BY id DESC LIMIT 1");
		}
		else {
			$sth = $ip_to_name_dbh->prepare("SELECT ip FROM ip_to_name WHERE name=? ORDER BY id DESC LIMIT 1");
		}
		if (   (!defined($ip_by_slot{$slot}))
			or ($ip_by_slot{$slot} eq 'not_yet_known'))
		{
			$ip_by_slot{$slot} = 'unknown';
			if ($guid_by_slot{$slot}) {
				$sth->execute($guid_by_slot{$slot})
				  or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
			}
			else {
				$sth->execute($name_by_slot{$slot})
				  or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
			}
			while (@row = $sth->fetchrow_array) {
				$ip_by_slot{$slot} = $row[0] . '?';
				if ($guid_by_slot{$slot}) {
					print "Guessed an IP by GUID for: $name_by_slot{$slot} = $ip_by_slot{$slot}\n";
				}
				else {
					print "Guessed an IP by NAME for: $name_by_slot{$slot} = $ip_by_slot{$slot}\n";
				}
			}
		}
	}

	# END: IP Guessing from cache
}

# END: status

# BEGIN: banned_ip_check($slot)
sub banned_ip_check {
	my $slot = shift;
	my @row;
	$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE ip=? AND unban_time > $time ORDER BY id DESC LIMIT 1");
	$bans_sth->execute($ip_by_slot{$slot});

	while (@row = $bans_sth->fetchrow_array) {
		if ($row[3] ne 'unknown') {
			&banned_player_kick($slot, $row[0], $row[1], $row[2], $row[3], $row[4], $row[5]);
		}
	}
}

# END: banned_ip_check

# BEGIN: banned_guid_check($slot)
sub banned_guid_check {
	my $slot = shift;
	my @row;
	$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE guid=? AND unban_time > $time ORDER BY id DESC LIMIT 1");
	$bans_sth->execute($guid_by_slot{$slot});

	while (@row = $bans_sth->fetchrow_array) {
		if ($row[4]) {
			&banned_player_kick($slot, $row[0], $row[1], $row[2], $row[3], $row[4], $row[5]);
		}
	}
}

# END: banned_guid_check

# BEGIN: banned_player_kick
sub banned_player_kick {
	my ($slot, $ban_id, $ban_time, $unban_time, $ban_ip, $ban_guid, $ban_name) = (@_);
	my $bandate;
	my $bantime;
	if (!$ban_message_spam) {
		$bantime = scalar(localtime($ban_time))->strftime;
		if ($bantime =~ /^(\w+),\s(\d+)\s(\w+)\s(\d+)\s(\d+:\d+:\d+)\s(\w+)$/) { $bantime = "$5 $6"; }    # Only display time and timezone
		$bandate = scalar(localtime($ban_time))->dmy(".");
		sleep 1;
		&rcon_command("say $name_by_slot{$slot}^7: You are banned. You are not allowed to stay on this server");
		sleep 1;
		&rcon_command("say $ban_name^7: Was banned ^3$bandate ^7in ^2$bantime ^7(BAN ID#: ^1$ban_id^7)");
		sleep 1;

		if ($unban_time == 2125091758) {
			&rcon_command("say $name_by_slot{$slot}^7: You are permanently banned.");
		}
		else {
			&rcon_command("say $name_by_slot{$slot}^7: You will be unbanned in " . &duration($unban_time - $time));
		}
		sleep 1;
		&log_to_file('logs/kick.log', "KICK: BANNED: $name_by_slot{$slot} was kicked - BANNED: IP - $ban_ip GUID - $ban_guid BAN ID# - $ban_id");
		&rcon_command("clientkick $slot");
		$ban_message_spam = $time + 3;    # 3 seconds spam protection
	}
}

# END: banned_player_kick

# BEGIN: rcon_command($command)
sub rcon_command {
	my ($command) = @_;
	my $error;

	# odd bug regarding double slashes.
	$command =~ s/\/\/+/\//g;
	$rcon->execute($command);
	&log_to_file('logs/rcon.log', "RCON: executed command: $command");
	if ($config->{'show_rcon'}) { print "RCON: $command\n"; }
	sleep 1;

	if ($error = $rcon->error) {

		# rcon timeout happens after the object has been in use for a long while.
		# Try rebuilding the object
		if ($error eq 'Rcon timeout') {
			print "rebuilding rcon object\n";
			$rcon = new KKrcon(
				Host     => $config->{'ip'},
				Port     => $config->{'port'},
				Password => $config->{'rcon_pass'},
				Type     => 'old'
			);
		}
		else { print "WARNING: rcon_command error: $error\n"; }
		return 1;
	}
	else { return 0; }
}

# END: rcon_command

# BEGIN: rcon_query($command)
sub rcon_query {
	my ($command) = @_;
	my $result;
	my $error;

	# odd bug regarding double slashes.
	$command =~ s/\/\/+/\//g;
	$result = $rcon->execute($command);
	&log_to_file('logs/rcon.log', "RCON: executed command: $command");
	if ($config->{'show_rcon'}) { print "RCON: $command\n"; }
	sleep 1;

	if ($error = $rcon->error) {

		# rcon timeout happens after the object has been in use for a long while.
		# Try rebuilding the object
		if ($error eq 'Rcon timeout') {
			print "rebuilding rcon object\n";
			$rcon = new KKrcon(
				Host     => $config->{'ip'},
				Port     => $config->{'port'},
				Password => $config->{'rcon_pass'},
				Type     => 'old'
			);
		}
		else { print "WARNING: rcon_command error: $error\n"; }
		return $result;
	}
	else { return $result; }
}

# END: rcon_query

# BEGIN: geolocate_ip
sub geolocate_ip {
	my $ip     = shift;
	my $metric = 1;
	if (!$ip) { return "No IP-Address has been defined"; }
	if ($ip =~ /^192\.168\.|^10\.|^169\.254\./) { return "Local Network"; }

	if ($ip !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
		return "Invalid IP-Address: $ip";
	}
	my $gi = Geo::IP->open("Geo/GeoLiteCity.dat", GEOIP_STANDARD);
	my $record = $gi->record_by_addr($ip);
	my $geo_ip_info;
	if (!$record) { return "No location found for this IP-Address"; }

	if (defined($record->country_code)) {
		print "\n\tCountry Code: " . $record->country_code . "\n";
	}
	if (defined($record->country_code3)) {
		print "\tCountry Code 3: " . $record->country_code3 . "\n";
	}
	if (defined($record->country_name)) {
		print "\tCountry Name: " . $record->country_name . "\n";
	}
	if (defined($record->region)) {
		print "\tRegion: " . $record->region . "\n";
	}
	if (defined($record->region_name)) {
		print "\tRegion Name: " . $record->region_name . "\n";
	}
	if (defined($record->city)) { print "\tCity: " . $record->city . "\n"; }
	if (defined($record->postal_code)) {
		print "\tPostal Code: " . $record->postal_code . "\n";
	}
	if (defined($record->latitude)) {
		print "\tLattitude: " . $record->latitude . "\n";
	}
	if (defined($record->longitude)) {
		print "\tLongitude: " . $record->longitude . "\n";
	}
	if (defined($record->time_zone)) {
		print "\tTime Zone: " . $record->time_zone . "\n";
	}
	if (defined($record->area_code)) {
		print "\tArea Code: " . $record->area_code . "\n";
	}
	if (defined($record->continent_code)) {
		print "\tContinent Code: " . $record->continent_code . "\n";
	}
	if (defined($record->metro_code)) {
		print "\tMetro Code " . $record->metro_code . "\n\n";
	}
	if ($record->city) {

		# we know the city
		if ($record->region_name) {

			# and we know the region name
			if ($record->city ne $record->region_name) {

				# the city and region name are different, all three are relevant.
				$geo_ip_info = $record->city . '^7,^2 ' . $record->region_name . ' ^7-^2 ' . $record->country_name;
			}
			else {
				# the city and region name are the same.  Use city and country.
				$geo_ip_info = $record->city . '^7,^2 ' . $record->country_name;
			}
		}
		else {
			# Only two pieces we have are city and country.
			$geo_ip_info = $record->city . '^7,^2 ' . $record->country_name;
		}
	}
	elsif ($record->region_name) {

		# don't know the city, but we know the region name and country.  close enough.
		$geo_ip_info = $record->region_name . '^7,^2 ' . $record->country_name;
	}
	elsif ($record->country_name) {

		# We may not know much, but we know the country.
		$geo_ip_info = $record->country_name;
	}
	elsif ($record->country_code3) {

		# How about a 3 letter country code?
		$geo_ip_info = $record->country_code3;
	}
	elsif ($record->country_code) {

		# How about a 2 letter country code at least?
		$geo_ip_info = $record->country_code;
	}
	else {
		# I give up.
		$geo_ip_info = "Unknown location";
	}
	if   ($record->country_code eq 'US') { $metric = 0; }
	else                                 { $metric = 1; }

	# GPS Coordinates
	if (($config->{'ip'} !~ /^192\.168\.|^10\.|^169\.254\./)) {
		if (    ($record->latitude)
			and ($record->longitude)
			and ($record->latitude =~ /\d/))
		{
			my ($player_lat, $player_lon) = ($record->latitude, $record->longitude);

			# gps coordinates are defined for this IP.
			# now make sure we have coordinates for the server.
			$record = $gi->record_by_addr($config->{'ip'});
			if (    ($record->latitude)
				and ($record->longitude)
				and ($record->latitude =~ /\d/))
			{
				my ($home_lat, $home_lon) = ($record->latitude, $record->longitude);
				my $obj = Geo::Inverse->new;
				my $dist = $obj->inverse($player_lat, $player_lon, $home_lat, $home_lon);
				if ($ip ne $config->{'ip'}) {

					if ($metric) {
						$dist = int($dist / 1000);
						$geo_ip_info .= "^7, ^1$dist ^7kilometers to the server";
					}
					else {
						$dist = int($dist / 1609.344);
						$geo_ip_info .= "^7, ^1$dist ^7miles to the server";
					}
				}
			}
		}
	}
	return $geo_ip_info;
}

# END geolocate_ip

# BEGIN: cache_guid_to_name(guid,name)
sub cache_guid_to_name {
	my $guid = shift;
	my $name = shift;
	my @row;

	# idiot gates
	if (!defined($guid)) {
		&die_nice("cache_guid_to_name was called without a guid number\n");
	}
	elsif ($guid !~ /^\d+$/) {
		&die_nice("cache_guid_to_name guid was not a number: $guid\n");
	}
	elsif (!defined($name)) {
		&die_nice("cache_guid_to_name was called without a name\n");
	}
	if ($guid) {

		# only log this if the guid isn't zero
		$guid_to_name_sth = $guid_to_name_dbh->prepare("SELECT count(*) FROM guid_to_name WHERE guid=? AND name=?");
		$guid_to_name_sth->execute($guid, $name)
		  or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
		@row = $guid_to_name_sth->fetchrow_array;
		if ($row[0]) { }
		else {
			&log_to_file('logs/guid.log', "Caching GUID to NAME mapping: $guid <-> $name");
			print "Caching GUID to NAME mapping: $guid <-> $name\n";
			$guid_to_name_sth = $guid_to_name_dbh->prepare("INSERT INTO guid_to_name VALUES (NULL, ?, ?)");
			$guid_to_name_sth->execute($guid, $name)
			  or &die_nice("Unable to do insert\n");
		}
	}
}

# END: cache_guid_to_name

# BEGIN: cache_ip_to_guid($ip,$guid)
sub cache_ip_to_guid {
	my $ip   = shift;
	my $guid = shift;
	my @row;

	# idiot gates
	if (!defined($guid)) {
		&die_nice("cache_ip_to_guid was called without a guid number\n");
	}
	elsif ($guid !~ /^\d+$/) {
		&die_nice("cache_ip_to_guid guid was not a number: $guid\n");
	}
	elsif (!defined($ip)) {
		&die_nice("cache_ip_to_guid was called without an ip\n");
	}
	if ($guid) {

		# only log this if the guid isn't zero
		$ip_to_guid_sth = $ip_to_guid_dbh->prepare("SELECT count(*) FROM ip_to_guid WHERE ip=? AND guid=?");
		$ip_to_guid_sth->execute($ip, $guid)
		  or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
		@row = $ip_to_guid_sth->fetchrow_array;
		if ($row[0]) { }
		else {
			&log_to_file('logs/guid.log', "New IP to GUID mapping: $ip <-> $guid");
			print "New IP to GUID mapping: $ip <-> $guid\n";
			$ip_to_guid_sth = $ip_to_guid_dbh->prepare("INSERT INTO ip_to_guid VALUES (NULL, ?, ?)");
			$ip_to_guid_sth->execute($ip, $guid)
			  or &die_nice("Unable to do insert\n");
		}
	}
}

# END: cache_ip_to_guid

# BEGIN: cache_ip_to_name($ip,$name)
sub cache_ip_to_name {
	my $ip   = shift;
	my $name = shift;
	my @row;

	# idiot gates
	if (!defined($name)) {
		&die_nice("cache_ip_to_name was called without a name\n");
	}
	elsif (!defined($ip)) {
		&die_nice("cache_ip_to_name was called without an ip\n");
	}
	$ip_to_name_sth = $ip_to_name_dbh->prepare("SELECT count(*) FROM ip_to_name WHERE ip=? AND name=?");
	$ip_to_name_sth->execute($ip, $name)
	  or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
	@row = $ip_to_name_sth->fetchrow_array;
	if ($row[0]) { }
	else {
		&log_to_file('logs/guid.log', "Caching IP to NAME mapping: $ip <-> $name");
		print "Caching IP to NAME mapping: $ip <-> $name\n";
		$ip_to_name_sth = $ip_to_name_dbh->prepare("INSERT INTO ip_to_name VALUES (NULL, ?, ?)");
		$ip_to_name_sth->execute($ip, $name)
		  or &die_nice("Unable to do insert\n");
	}
}

# END: cache_ip_to_name

# BEGIN: !seen($search_string)
sub seen {
	my @row;
	if (&flood_protection('seen', 30, $slot)) { return 1; }
	my $search_string = shift;
	$seen_sth = $seen_dbh->prepare("SELECT name,time,saying FROM seen WHERE name LIKE ? ORDER BY time DESC LIMIT 5");
	$seen_sth->execute("\%$search_string\%")
	  or &die_nice("Unable to execute query: $seen_dbh->errstr\n");

	while (@row = $seen_sth->fetchrow_array) {
		&rcon_command("say $row[0] ^7was last seen " . duration($time - $row[1]) . " ago and said: $row[2]");
		sleep 1;
	}
}

# END: seen

# BEGIN: log_to_file($file, $message)
sub log_to_file {
	my ($logfile, $msg) = @_;
	open LOG, ">> $logfile" or return 0;
	print LOG "$currentdate $currenttime $msg\n";
	close LOG;
}

# END: log_to_file

# BEGIN: !lastkill($search_string)
sub lastkill {
	if (&flood_protection('lastkill', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	if ($search_string) {
		my @matches = &matching_users($search_string);
		if (    ($#matches == 0)
			and (defined($last_kill_by_name{$matches[0]}))
			and ($last_kill_by_name{$matches[0]} ne 'none'))
		{
			&rcon_command("say $name_by_slot{$matches[0]} ^7killed $last_kill_by_name{$matches[0]}");
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
	}
	elsif ( (defined($last_kill_by_name{$slot}))
		and ($last_kill_by_name{$slot} ne 'none'))
	{
		&rcon_command("say $name_by_slot{$slot}^7: You killed $last_kill_by_name{$slot}");
	}
}

# END: lastkill

# BEGIN: !lastkilled($search_string)
sub lastkilled {
	if (&flood_protection('lastkilled', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	if ($search_string) {
		my @matches = &matching_users($search_string);
		if (    ($#matches == 0)
			and (defined($last_killed_by_name{$matches[0]}))
			and ($last_killed_by_name{$matches[0]} ne 'none'))
		{
			&rcon_command("say $name_by_slot{$matches[0]} ^7was killed by $last_killed_by_name{$matches[0]}");
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
	}
	elsif ( (defined($last_killed_by_name{$slot}))
		and ($last_killed_by_name{$slot} ne 'none'))
	{
		&rcon_command("say $name_by_slot{$slot}^7: You were killed by $last_killed_by_name{$slot}");
	}
}

# END: lastkilled

# BEGIN: !stats($search_string)
sub stats {
	my $slot          = shift;
	my $search_string = shift;
	my @row;
	if ($search_string) {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
	}
	if (&flood_protection('stats', 30)) { return 1; }
	$name = $name_by_slot{$slot};
	$guid = $guid_by_slot{$slot};
	my $stats_msg = "Stats $name^7:";
	$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE guid=?");
	$stats_sth->execute($guid)
	  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	@row = $stats_sth->fetchrow_array;

	if ($row[0]) {

		# kills, deaths, headshots
		my $kills     = $row[2];
		my $deaths    = $row[3];
		my $headshots = $row[4];
		$stats_msg .= " ^2$kills ^7kills, ^1$deaths ^7deaths, ^3$headshots ^7headshots, ";

		# k2d_ratio
		if ($row[2] and $row[3]) {
			my $k2d_ratio = int($row[2] / $row[3] * 100) / 100;
			$stats_msg .= "^8$k2d_ratio ^7k/d ratio, ";
		}

		# headshot_percent
		if ($row[2] and $row[4]) {
			my $headshot_percent = int($row[4] / $row[2] * 10000) / 100;
			$stats_msg .= "^3$headshot_percent ^7headshots percentage";
		}
		&rcon_command("say $stats_msg");
		sleep 1;
		$stats_msg = "Stats $name^7:";

		# pistol_ratio,grenade_ratio,bash_ratio
		if ($row[2]) {
			my $pistol_ratio =
			  ($row[5]) ? int($row[5] / $row[2] * 10000) / 100 : 0;
			my $grenade_ratio =
			  ($row[6]) ? int($row[6] / $row[2] * 10000) / 100 : 0;
			my $bash_ratio =
			  ($row[7]) ? int($row[7] / $row[2] * 10000) / 100 : 0;
			$stats_msg .= " ^9$pistol_ratio ^7pistol ratio, ^9$grenade_ratio ^7grenade ratio, ^9$bash_ratio ^7melee ratio";

			if (($row[5]) or ($row[6]) or ($row[7])) {
				&rcon_command("say $stats_msg");
				sleep 1;
			}

			# shotgun_ratio,sniper_ratio,rifle_ratio,machinegun_ratio
			$stats_msg = "Stats $name^7:";
			my $shotgun_ratio =
			  (($row[8]) and ($row[2]))
			  ? int($row[8] / $row[2] * 10000) / 100
			  : 0;
			my $sniper_ratio =
			  (($row[9]) and ($row[2]))
			  ? int($row[9] / $row[2] * 10000) / 100
			  : 0;
			my $rifle_ratio =
			  (($row[10]) and ($row[2]))
			  ? int($row[10] / $row[2] * 10000) / 100
			  : 0;
			my $machinegun_ratio =
			  (($row[11]) and ($row[2]))
			  ? int($row[11] / $row[2] * 10000) / 100
			  : 0;
			$stats_msg .= " ^9$shotgun_ratio ^7shotgun ratio, ^9$sniper_ratio ^7sniper ratio, ^9$rifle_ratio ^7rifle ratio, ^9$machinegun_ratio ^7machinegun ratio";

			if (   ($row[8])
				or ($row[9])
				or ($row[10])
				or ($row[11]))
			{
				&rcon_command("say $stats_msg");
				sleep 1;
			}

			# best_killspree
			my $best_killspree = $row[12];
			if ($best_killspree and ($config->{'killing_sprees'})) {
				$stats_msg = "Stats $name^7:";
				$stats_msg .= " Best killing spree - ^6$best_killspree";
				&rcon_command("say $stats_msg");
				sleep 1;
			}

			# nice_shots
			my $nice_shots = $row[13];
			my $niceshot_ratio =
			  (($row[13]) and ($row[2]))
			  ? int($row[13] / $row[2] * 10000) / 100
			  : 0;
			if (($nice_shots) and ($config->{'nice_shots'})) {
				$stats_msg = "Stats $name^7:";
				$stats_msg .= " Nice shots: ^2$row[13] ^7(^2$niceshot_ratio ^7percent)";
				&rcon_command("say $stats_msg");
				sleep 1;
			}

			# bad_shots
			my $bad_shots = $row[14];
			my $badshot_ratio =
			  (($row[14]) and ($row[2]))
			  ? int($row[14] / $row[2] * 10000) / 100
			  : 0;
			if (($bad_shots) and ($config->{'bad_shots'})) {
				$stats_msg = "Stats $name^7:";
				$stats_msg .= " Bad shots: ^1$row[14] ^7(^1$badshot_ratio ^7percent)";
				&rcon_command("say $stats_msg");
				sleep 1;
			}

			# first_bloods
			my $first_bloods = $row[15];
			if (($first_bloods) and ($config->{'first_blood'})) {
				$stats_msg = "Stats $name^7:";
				$stats_msg .= " First bloods: ^1$first_bloods";
				&rcon_command("say $stats_msg");
				sleep 1;
			}
		}
		if ($gametype eq 'sd') {

			# bomb_plants
			my $bomb_plants = $row[16];
			if ($bomb_plants) {
				$stats_msg = "Stats $name^7:";
				$stats_msg .= " Bomb plants: ^4$bomb_plants";
				&rcon_command("say $stats_msg");
				sleep 1;
			}

			# bomb_defuses
			my $bomb_defuses = $row[17];
			if ($bomb_defuses) {
				$stats_msg = "Stats $name^7:";
				$stats_msg .= " Bomb defuses: ^5$bomb_defuses";
				&rcon_command("say $stats_msg");
				sleep 1;
			}
		}
	}
	elsif ($guid) {
		&rcon_command("say No stats found for: $name");
		$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)");
		$stats_sth->execute($guid, 0, 0, 0)
		  or &die_nice("Unable to do insert\n");
	}
	else {
		&rcon_command("say Error reading stats for: $name^7 (^2GUID^7 - ^3$guid^7)");
	}
}

# END: stats

# BEGIN: check_access($attribute_name)
sub check_access {
	my $attribute = shift;
	my $value;

	if (!defined($attribute)) {
		&die_nice("check_access was called without an attribute");
	}
	if (defined($config->{'auth'}->{$attribute})) {

		# Helpful globals from the chat function
		# $name
		# $slot
		# $message
		# $guid

		# Check each specific attribute defined for this specific directive.
		foreach $value (split /,/, $config->{'auth'}->{$attribute}) {
			if ($value =~ /disabled/i) {

				# The command has been disabled.
				# Check to see if this person has override access
				if (defined($config->{'auth'}->{'override'})) {

					# Check each specific attribute defined for the 'override' directive.
					foreach $value (split /,/, $config->{'auth'}->{'override'}) {

						# Check if this is a GUID
						if ($value =~ /^\d+$/) {
							if ($guid eq $value) {
								print "disabled command $attribute authenticated by GUID override access: $value\n";
								return 1;
							}

							# Check if this is an exact IP match
						}
						elsif ($value =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
							if ($ip_by_slot{$slot} eq $value) {
								print "disabled command $attribute authenticated by IP override access: $value\n";
								return 1;
							}

							# Check if the IP is a wildcard match
						}
						elsif ($value =~ /^\d{1,3}\.\d{1,3}\.[\d\.]+\.\*$/) {
							$value =~ s/\./\\./g;
							if ($ip_by_slot{$slot} =~ /$value/) {

								# no guessed IPs allowed
								if ($ip_by_slot{$slot} =~ /\?$/) {
									print "Refusing to authenticate a guessed IP address\n";
								}
								else {
									print "disabled command $attribute authenticated by wildcard IP override access: $value\n";
									return 1;
								}
							}
						}
						else {
							print "\nWARNING: unrecognized $attribute access directive:  $value\n\n";
						}
					}
				}

				# if we made it this far, then there were no overrides.
				# consider the command disabled.
				return 0;
			}
			if ($value =~ /everyone/i) { return 1; }

			# Check if this is a GUID
			if ($value =~ /^\d+$/) {
				if ($guid eq $value) {
					print "$attribute command authenticated by GUID: $value\n";
					return 1;
				}

				# Check if this is an exact IP match
			}
			elsif ($value =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
				if ($ip_by_slot{$slot} eq $value) {
					print "$attribute command authenticated by IP: $value\n";
					return 1;
				}

				# Check if the IP is a wildcard match
			}
			elsif ($value =~ /^\d{1,3}\.\d{1,3}\.[\d\.]+\.\*$/) {
				$value =~ s/\./\\./g;
				if ($ip_by_slot{$slot} =~ /$value/) {

					# no guessed IPs allowed
					if ($ip_by_slot{$slot} =~ /\?$/) {
						print "Refusing to authenticate a guessed IP address\n";
					}
					else {
						print "$attribute command authenticated by wildcard IP: $value\n";
						return 1;
					}
				}
			}
			else {
				print "\nWARNING: unrecognized access directive:  $value\n\n";
			}
		}
	}

	# Since nothing above was a match...
	# Check to see if they have global access to all commands
	if (    (defined($config->{'auth'}->{'everything'}))
		and ($attribute ne 'disabled'))
	{
		foreach $value (split /,/, $config->{'auth'}->{'everything'}) {
			if ($value =~ /^everyone$/i) { return 1; }

			# Check if this is a GUID
			if ($value =~ /^\d+$/) {
				if ($guid eq $value) {
					print "global admin access for $attribute authenticated by GUID: $value\n";
					return 1;
				}

				# Check if this is an exact IP match
			}
			elsif ($value =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
				if ($ip_by_slot{$slot} eq $value) {
					print "global admin access for $attribute authenticated by IP: $value\n";
					return 1;
				}

				# Check if the IP is a wildcard match
			}
			elsif ($value =~ /^\d{1,3}\.\d{1,3}\.[\d\.]+\.\*$/) {
				$value =~ s/\./\\./g;
				if ($ip_by_slot{$slot} =~ /$value/) {

					# make sure that we dont let guessed IP's through
					if ($ip_by_slot{$slot} =~ /\?$/) {
						print "Refusing to authenticate a guessed IP address\n";
					}
					else {
						print "global admin access for $attribute authenticated by wildcard IP: $value\n";
						return 1;
					}
				}
			}
			else {
				print "\nWARNING: unrecognized access directive:  $value\n\n";
			}
		}
	}
	return 0;
}

# END: check_access

# BEGIN: sanitize_regex($search_string)
sub sanitize_regex {
	my $search_string = shift;
	if (!defined($search_string)) {
		print "WARNING: sanitize_regex was not passed a string\n";
		return '';
	}
	if ($search_string eq 'all') { return '.'; }

	$search_string =~ s/\\/\\\\/g;
	$search_string =~ s/\./\\./g;
	$search_string =~ s/\*/\\*/g;
	$search_string =~ s/\?/\\?/g;
	$search_string =~ s/\|/\\|/g;
	$search_string =~ s/\+/\\+/g;
	$search_string =~ s/\^/\\^/g;
	$search_string =~ s/\(/\\\(/g;
	$search_string =~ s/\)/\\\)/g;
	$search_string =~ s/\[/\\\[/g;
	$search_string =~ s/\]/\\\]/g;
	$search_string =~ s/\$/\\\$/g;
	$search_string =~ s/\%/\\\%/g;
	$search_string =~ s/\@/\\\@/g;
	$search_string =~ s/\{/\\\{/g;
	$search_string =~ s/\}/\\\}/g;

	return $search_string;
}

# END: sanitize_regex

# BEGIN: matching_users($search_string)
sub matching_users {

	# a generic function to do string matches on active usernames
	# returns a list of slot numbers that match.
	my $search_string = shift;
	if   ($search_string =~ /^\/(.+)\/$/) { $search_string = $1; }
	else                                  { $search_string = &sanitize_regex($search_string); }
	my $key;
	my @matches;

	foreach $key (keys %name_by_slot) {
		if (   ($name_by_slot{$key} =~ /$search_string/i)
			or (&strip_color($name_by_slot{$key}) =~ /$search_string/i)
			or (&strip_space($name_by_slot{$key}) =~ /$search_string/i))
		{
			if ($name_by_slot{$key} ne 'SLOT_EMPTY') {
				print "MATCH: $name_by_slot{$key}\n";
				push @matches, $key;
			}
		}
	}
	return @matches;
}

# END: matching_users

# BEGIN: !ignore($search_string)
sub ignore {
	if (&flood_protection('ignore', 30, $slot)) { return 1; }
	my $search_string = shift;
	if ($search_string =~ /^\#(\d+)$/) { $slot = $1; }
	else {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	if ($name_by_slot{$slot} eq 'SLOT_EMPTY') { return 1; }
	$ignore{$slot} = 1;
	&rcon_command("say $name_by_slot{$slot} ^7will be ignored now.");
	&log_to_file('logs/admin.log', "!IGNORE: $name_by_slot{$slot} was ignored by $name - GUID $guid (Search: $search_string)");
}

# END: ignore

# BEGIN: !forgive($search_string)
sub forgive {
	if (&flood_protection('forgive', 30, $slot)) { return 1; }
	my $search_string = shift;
	if ($search_string =~ /^\#(\d+)$/) { $slot = $1; }
	else {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	if ($name_by_slot{$slot} eq 'SLOT_EMPTY') { return 1; }
	$ignore{$slot}                = 0;
	$idle_warn_level{$slot}       = 0;
	$last_activity_by_slot{$slot} = $time;
	$penalty_points{$slot}        = 0;
	$spam_count{$slot}            = 0;
	$spam_last_said{$slot}        = &random_pwd(16);
	&rcon_command("say $name_by_slot{$slot} ^7was forgiven by an admin");
	&log_to_file('logs/admin.log', "!FORGIVE: $name_by_slot{$slot} was forgiven by $name - GUID $guid (Search: $search_string)");
}

# END: forgive

# BEGIN: !clearstats($search_string)
sub clear_stats {
	if (&flood_protection('clearstats', 30, $slot)) { return 1; }
	my $search_string = shift;
	my @matches       = &matching_users($search_string);
	if ($#matches == 0) {
		$stats_sth = $stats_dbh->prepare("DELETE FROM stats where guid=?;");
		$stats_sth->execute($guid_by_slot{$matches[0]})
		  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		&rcon_command("say Removed stats for: $name_by_slot{$matches[0]}");
		&log_to_file('logs/admin.log', "!CLEARSTATS: $name_by_slot{$matches[0]} (GUID - $guid_by_slot{$matches[0]}) stats were deleted by $name - GUID $guid (Search: $search_string)");
	}
	elsif ($#matches == -1) {
		&rcon_command("say No matches for: $search_string");
		return 1;
	}
	elsif ($#matches > 0) {
		&rcon_command("say Too many matches for: $search_string");
		return 1;
	}
}

# END: clearstats

# BEGIN: !clearnames($search_string)
sub clear_names {
	if (&flood_protection('clearnames', 30, $slot)) { return 1; }
	my $search_string = shift;
	my @matches       = &matching_users($search_string);
	if ($#matches == 0) {
		if ($ip_by_slot{$matches[0]} =~ /\?$/) { return 1; }
		$guid_to_name_sth = $guid_to_name_dbh->prepare("DELETE FROM guid_to_name where guid=?;");
		$guid_to_name_sth->execute($guid_by_slot{$matches[0]})
		  or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
		$ip_to_name_sth = $ip_to_name_dbh->prepare("DELETE FROM ip_to_name where ip=?;");
		$ip_to_name_sth->execute($ip_by_slot{$matches[0]})
		  or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
		&rcon_command("say Removed names for: $name_by_slot{$matches[0]}");
		&log_to_file('logs/admin.log', "!CLEARNAMES: $name_by_slot{$matches[0]} names were deleted by $name - GUID $guid (Search: $search_string)");
	}
	elsif ($#matches == -1) {
		&rcon_command("say No matches for: $search_string");
		return 1;
	}
	elsif ($#matches > 0) {
		&rcon_command("say Too many matches for: $search_string");
		return 1;
	}
}

# END: clearnames

# BEGIN: !report($search_string)
sub report_player {
	if (&flood_protection('report', 30)) { return 1; }
	my $search_string = shift;
	my $reason        = shift;
	my @matches       = &matching_users($search_string);
	if ($#matches == 0) {
		&rcon_command("say Report for $name_by_slot{$matches[0]} ^7has been sent to an admin.");
		&log_to_file('logs/report.log', "!report: $name_by_slot{$slot} - GUID $guid reported player $name_by_slot{$matches[0]} - GUID $guid_by_slot{$matches[0]} - reason $reason via the !report command (Search: $search_string)");
	}
	elsif ($#matches == -1) {
		&rcon_command("say No matches for: $search_string");
		return 1;
	}
	elsif ($#matches > 0) {
		&rcon_command("say Too many matches for: $search_string");
		return 1;
	}
}

# END: report

# BEGIN: !ip($search_string)
sub ip_player {
	if (&flood_protection('ip', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	if ($search_string) {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	&rcon_command("say IP-Address: $name_by_slot{$slot}^7 - ^2$ip_by_slot{$slot}");
}

# END: ip

# BEGIN: !id($search_string)
sub id_player {
	if (&flood_protection('id', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	if ($search_string) {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	&rcon_command("say ClientID: $name_by_slot{$slot}^7 - ^1$slot");
}

# END: id

# BEGIN: !guid($search_string)
sub guid_player {
	if (&flood_protection('guid', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	if ($search_string) {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	&rcon_command("say GUID: $name_by_slot{$slot}^7 - ^3$guid_by_slot{$slot}");
}

# END: guid

# BEGIN: !age($search_string)
sub age_player {
	if (&flood_protection('age', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	my $age           = 10 + int(rand(25 - 5));
	if ($search_string) {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	&rcon_command("say Approximate age for $name_by_slot{$slot}^7 - ^3$age ^7years");
}

# END: age

# BEGIN: !name($search_string)
sub name_player {
	if (&flood_protection('name', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	my @row;

	if ($search_string) {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	$names_sth = $names_dbh->prepare("SELECT * FROM names ORDER BY RANDOM() LIMIT 1;");
	$names_sth->execute()
	  or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	@row = $names_sth->fetchrow_array;

	if (!$row[0]) {
		&rcon_command("say Unfortunately, no names has been found in database");
	}
	else { &rcon_command("say $name_by_slot{$slot} ^7name is ^3$row[1]"); }
}

# END: name

# BEGIN: !rank($search_string)
sub rank_player {
	if (&flood_protection('rank', 30, $slot)) { return 1; }
	my $slot          = shift;
	my $search_string = shift;
	my @row;

	if ($search_string) {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	$ranks_sth = $ranks_dbh->prepare("SELECT * FROM ranks ORDER BY RANDOM() LIMIT 1;");
	$ranks_sth->execute()
	  or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
	@row = $ranks_sth->fetchrow_array;

	if (!$row[0]) {
		&rcon_command("say Unfortunately, no ranks has been found in database");
	}
	else {
		&rcon_command("say $name_by_slot{$slot}^7: Your rank is: ^3$row[1]");
	}
}

# END: rank

# BEGIN: !addname($name)
sub add_name {
	if (&flood_protection('addname', 30, $slot)) { return 1; }
	my @row;
	my $name = shift;
	if (!defined($name)) {
		&die_nice("!addname was called without a name\n");
	}
	$names_sth = $names_dbh->prepare("SELECT count(*) FROM names WHERE name=?");
	$names_sth->execute($name)
	  or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	@row = $names_sth->fetchrow_array;

	if ($row[0]) {
		&rcon_command("say Name ^2$name ^7already exist in database");
	}
	else {
		$names_sth = $names_dbh->prepare("INSERT INTO names VALUES (NULL, ?)");
		$names_sth->execute($name) or &die_nice("Unable to do insert\n");
		&rcon_command("say Name ^2$name ^7has beed added to database");
	}
}

# END: addname

# BEGIN: !addrank($rank)
sub add_rank {
	if (&flood_protection('addrank', 30, $slot)) { return 1; }
	my $rank = shift;
	my @row;
	if (!defined($rank)) {
		&die_nice("!addrank was called without a rank\n");
	}
	$ranks_sth = $ranks_dbh->prepare("SELECT count(*) FROM ranks WHERE rank=?");
	$ranks_sth->execute($rank)
	  or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
	@row = $ranks_sth->fetchrow_array;

	if ($row[0]) {
		&rcon_command("say Rank ^2$rank ^7already exist in database");
	}
	else {
		$ranks_sth = $ranks_dbh->prepare("INSERT INTO ranks VALUES (NULL, ?)");
		$ranks_sth->execute($rank) or &die_nice("Unable to do insert\n");
		&rcon_command("say Rank ^2$rank ^7has beed added to database");
	}
}

# END: addrank

# BEGIN: !clearname($name)
sub clear_name {
	if (&flood_protection('clearname', 30, $slot)) { return 1; }
	my $name = shift;
	my @row;
	if (!defined($name)) {
		&die_nice("!clearname was called without a name\n");
	}
	$names_sth = $names_dbh->prepare("SELECT count(*) FROM names WHERE name=?");
	$names_sth->execute($name)
	  or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	@row = $names_sth->fetchrow_array;

	if ($row[0]) {
		$names_sth = $names_dbh->prepare("DELETE FROM names WHERE name=?");
		$names_sth->execute($name)
		  or &die_nice("Unable to execute query: $names_dbh->errstr\n");
		&rcon_command("say Name ^2$name ^7 has been removed from database");
	}
	else { &rcon_command("say Name ^2$name ^7not found in database"); }
}

# END: clearname

# BEGIN: !clearrank($rank)
sub clear_rank {
	if (&flood_protection('clearrank', 30, $slot)) { return 1; }
	my $rank = shift;
	my @row;
	if (!defined($rank)) {
		&die_nice("!clearrank was called without a rank\n");
	}
	$ranks_sth = $ranks_dbh->prepare("SELECT count(*) FROM ranks WHERE rank=?");
	$ranks_sth->execute($rank)
	  or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
	@row = $ranks_sth->fetchrow_array;

	if ($row[0]) {
		$ranks_sth = $ranks_dbh->prepare("DELETE FROM ranks WHERE rank=?");
		$ranks_sth->execute($rank)
		  or &die_nice("Unable to execute query: $names_dbh->errstr\n");
		&rcon_command("say Rank ^2$rank ^7has been removed from database");
	}
	else { &rcon_command("say Rank ^2$rank ^7not found in database"); }
}

# END: clearrank

# BEGIN: database_info($database)
sub database_info {
	if (&flood_protection('dbinfo', 30, $slot)) { return 1; }
	my $message = shift;
	my @row;
	if ($message =~ /^bans(.db)?$/i) {
		$bans_sth = $bans_dbh->prepare("SELECT count(*) FROM bans");
		$bans_sth->execute()
		  or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
		@row = $bans_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2bans.db");
		}
		else { &rcon_command("say There are no records in ^2bans.db"); }
	}
	elsif ($message =~ /^definitions(.db)?$/i) {
		$definitions_sth = $definitions_dbh->prepare("SELECT count(*) FROM definitions");
		$definitions_sth->execute()
		  or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
		@row = $definitions_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2definitions.db");
		}
		else {
			&rcon_command("say There are no records in ^2definitions.db");
		}
	}
	elsif ($message =~ /^guid_to_name(.db)?$/i) {
		$guid_to_name_sth = $guid_to_name_dbh->prepare("SELECT count(*) FROM guid_to_name");
		$guid_to_name_sth->execute()
		  or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
		@row = $guid_to_name_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2guid_to_name.db");
		}
		else {
			&rcon_command("say There are no records in ^2guid_to_name.db");
		}
	}
	elsif ($message =~ /^ip_to_guid(.db)?$/i) {
		$ip_to_guid_sth = $ip_to_guid_dbh->prepare("SELECT count(*) FROM ip_to_guid");
		$ip_to_guid_sth->execute()
		  or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
		@row = $ip_to_guid_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2ip_to_guid.db");
		}
		else { &rcon_command("say There are no records in ^2ip_to_guid.db"); }
	}
	elsif ($message =~ /^ip_to_name(.db)?$/i) {
		$ip_to_name_sth = $ip_to_name_dbh->prepare("SELECT count(*) FROM ip_to_name");
		$ip_to_name_sth->execute()
		  or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
		@row = $ip_to_name_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2ip_to_name.db");
		}
		else { &rcon_command("say There are no records in ^2ip_to_name.db"); }
	}
	elsif ($message =~ /^names(.db)?$/i) {
		$names_sth = $names_dbh->prepare("SELECT count(*) FROM names");
		$names_sth->execute()
		  or &die_nice("Unable to execute query: $names_dbh->errstr\n");
		@row = $names_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2names.db");
		}
		else { &rcon_command("say There are no records in ^2names.db"); }
	}
	elsif ($message =~ /^ranks(.db)?$/i) {
		$ranks_sth = $ranks_dbh->prepare("SELECT count(*) FROM ranks");
		$ranks_sth->execute()
		  or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
		@row = $ranks_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2ranks.db");
		}
		else { &rcon_command("say There are no records in ^2ranks.db"); }
	}
	elsif ($message =~ /^seen(.db)?$/i) {
		$seen_sth = $seen_dbh->prepare("SELECT count(*) FROM seen");
		$seen_sth->execute()
		  or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
		@row = $seen_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2seen.db");
		}
		else { &rcon_command("say There are no records in ^2seen.db"); }
	}
	elsif ($message =~ /^stats(.db)?$/i) {
		$stats_sth = $stats_dbh->prepare("SELECT count(*) FROM stats");
		$stats_sth->execute()
		  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		@row = $stats_sth->fetchrow_array;
		if ($row[0]) {
			&rcon_command("say ^3$row[0] ^7records in ^2stats.db");
		}
		else { &rcon_command("say There are no records in ^2stats.db"); }
	}
	else {
		&rcon_command("say Invalid database: $message");
		sleep 1;
		&rcon_command("say Valid databases: ^2bans.db^7, ^2definitions.db^7, ^2guid_to_name.db");
		sleep 1;
		&rcon_command("say Valid databases: ^2ip_to_guid.db^7, ^2ip_to_name.db^7, ^2names.db^7, ^2ranks.db");
		sleep 1;
		&rcon_command("say Valid databases: ^2seen.db^7, ^2stats.db");
	}
}

# END: database_info

# BEGIN: !kick($search_string)
sub kick_command {
	if (&flood_protection('kick', 30, $slot)) { return 1; }
	my $search_string = shift;
	if ($search_string =~ /^\#(\d+)$/) { $slot = $1; }
	else {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	if ($name_by_slot{$slot} eq 'SLOT_EMPTY') { return 1; }
	&rcon_command("say $name_by_slot{$slot} ^7was kicked by an admin");
	sleep 1;
	&rcon_command("clientkick $slot");
	&log_to_file('logs/kick.log', "!KICK: $name_by_slot{$slot} was kicked by $name - GUID $guid - via the !kick command. (Search: $search_string)");
}

# END: kick

# BEGIN: !tempban($search_string)
sub tempban_command {
	if (&flood_protection('tempban', 30, $slot)) { return 1; }
	my $search_string = shift;
	my $tempbantime   = shift;
	if (!defined($tempbantime))        { $tempbantime = 30; }
	if ($search_string =~ /^\#(\d+)$/) { $slot        = $1; }
	else {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	if ($name_by_slot{$slot} eq 'SLOT_EMPTY') { return 1; }
	my $ban_name   = 'unknown';
	my $ban_ip     = 'unknown';
	my $ban_guid   = 0;
	my $unban_time = $time + $tempbantime * 60;
	&rcon_command("say $name_by_slot{$slot} ^7was temporarily banned by an admin for ^3$tempbantime ^7minutes");
	if ($name_by_slot{$slot}) { $ban_name = $name_by_slot{$slot}; }

	if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
		$ban_ip = $ip_by_slot{$slot};
	}
	if ($guid_by_slot{$slot}) { $ban_guid = $guid_by_slot{$slot}; }
	$bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
	$bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name)
	  or &die_nice("Unable to do insert\n");
	&rcon_command("clientkick $slot");
	&log_to_file('logs/kick.log', "TEMPBAN: $name_by_slot{$slot} was temporarily banned by $name - GUID $guid - via the !tempban command. (Search: $search_string)");
	$ban_message_spam = $time + 3;    # 3 seconds spam protection
}

# END: tempban

# BEGIN: !ban($search_string)
sub ban_command {
	if (&flood_protection('ban', 30, $slot)) { return 1; }
	my $search_string = shift;
	if ($search_string =~ /^\#(\d+)$/) { $slot = $1; }
	else {
		my @matches = &matching_users($search_string);
		if ($#matches == 0) { $slot = $matches[0]; }
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $search_string");
			return 1;
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $search_string");
			return 1;
		}
	}
	if ($name_by_slot{$slot} eq 'SLOT_EMPTY') { return 1; }
	my $ban_name   = 'unknown';
	my $ban_ip     = 'unknown';
	my $ban_guid   = 0;
	my $unban_time = 2125091758;
	&rcon_command("say $name_by_slot{$slot} ^7was permanently banned by an admin");
	if ($name_by_slot{$slot}) { $ban_name = $name_by_slot{$slot}; }

	if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
		$ban_ip = $ip_by_slot{$slot};
	}
	if ($guid_by_slot{$slot}) { $ban_guid = $guid_by_slot{$slot}; }
	$bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
	$bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name)
	  or &die_nice("Unable to do insert\n");
	&rcon_command("clientkick $slot");
	&log_to_file('logs/kick.log', "BAN: $name_by_slot{$slot} was permanently banned by $name - GUID $guid - via the !ban command. (Search: $search_string)");
	$ban_message_spam = $time + 3;    # 3 seconds spam protection
}

# END: ban

# BEGIN: !unban($target);
#  where $target = a ban ID # or a partial string match for names.
sub unban_command {
	if (&flood_protection('unban', 30, $slot)) { return 1; }
	my $unban = shift;
	my $key;
	my @unban_these;
	my @row;

	if ($unban =~ /^\#?(\d+)$/) {
		$unban    = $1;
		$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE id=?");
	}
	else {
		$unban    = '%' . $unban . '%';
		$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE name LIKE ?");
	}
	$bans_sth->execute($unban)
	  or &die_nice("Unable to do unban SELECT: $unban\n");
	while (@row = $bans_sth->fetchrow_array) {
		&rcon_command("say $row[5] ^7was unbanned (BAN ID#: ^1$row[0] ^7deleted)");
		push(@unban_these, $row[0]);
		&log_to_file('logs/admin.log', "!UNBAN: $row[5] was unbanned by an admin. (BAN ID#: $row[0] deleted)");
	}

	# now clean up the database ID's.
	foreach $key (@unban_these) {
		$bans_sth = $bans_dbh->prepare("DELETE FROM bans WHERE id=?");
		$bans_sth->execute($key)
		  or &die_nice("Unable to delete ban ID $key: unban = $unban\n");
	}
}

# END: unban

# BEGIN: !voting($state)
sub voting_command {
	if (&flood_protection('voting', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("g_allowVote 1");
		&rcon_command("say Voting enabled.");
		$voting = 1;
		&log_to_file('logs/admin.log', "!VOTING: voting was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("g_allowVote 0");
		&rcon_command("say Voting disabled.");
		$voting = 0;
		&log_to_file('logs/admin.log', "!VOTING: voting was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !voting: $state, use on or off");
	}
}

# END: voting

# BEGIN: !voice($state)
sub voice_command {
	if (&flood_protection('voice', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("sv_voice 1");
		&rcon_command("say Voice chat enabled.");
		$voice = 1;
		&log_to_file('logs/admin.log', "!VOICE: voice chat was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("sv_voice 0");
		&rcon_command("say Voice chat disabled.");
		$voice = 0;
		&log_to_file('logs/admin.log', "!VOICE: voice chat was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !voice: $state, use on or off");
	}
}

# END: voice

# BEGIN: !antilag($state)
sub antilag_command {
	if (&flood_protection('antilag', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("g_antilag 1");
		&rcon_command("say Antilag enabled.");
		$antilag = 1;
		&log_to_file('logs/admin.log', "!ANTILAG: antilag was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("g_antilag 0");
		&rcon_command("say Antilag disabled.");
		$antilag = 0;
		&log_to_file('logs/admin.log', "!ANTILAG: antilag was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !antilag: $state, use on or off");
	}
}

# END: antilag

# BEGIN: !killcam($state)
sub killcam_command {
	if (&flood_protection('killcam', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("scr_killcam 1");
		&rcon_command("say Killcan was ^2ENABLED ^7by an admin");
		$killcam = 1;
		&log_to_file('logs/admin.log', "!KILLCAM: the kill-cam was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("scr_killcam 0");
		&rcon_command("say Killcam was ^1DISABLED ^7by an admin");
		$killcam = 0;
		&log_to_file('logs/admin.log', "!KILLCAM: the kill-cam was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !killcam: $state, use on or off");
	}
}

# END: killcam

# BEGIN: !forcerespawn($state)
sub forcerespawn_command {
	if (&flood_protection('forcerespawn', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("scr_forcerespawn 1");
		&rcon_command("say Forcerespawn was ^2ENABLED ^7by an admin");
		&log_to_file('logs/admin.log', "!FORCERESPAWN: the quick respawn was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("scr_forcerespawn 0");
		&rcon_command("say Forcerespawn was ^1DISABLED ^7by an admin");
		&log_to_file('logs/admin.log', "!FORCERESPAWN: the quick respawn was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !forcerespawn: $state, use on or off");
	}
}

# END: forcerespawn

# BEGIN: !teambalance($state)
sub teambalance_command {
	if (&flood_protection('teambalance', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("scr_teambalance 1");
		&rcon_command("say Teams auto-balance was ^2ENABLED ^7by an admin");
		&log_to_file('logs/admin.log', "!TEAMBALANCE: the team auto-balance was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("scr_teambalance 0");
		&rcon_command("say Teams auto-balance was ^1DISABLED ^7by an admin");
		&log_to_file('logs/admin.log', "!TEAMBALANCE: the team auto-balance was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !teambalance: $state, use on or off");
	}
}

# END: teambalance

# BEGIN: !spectatefree($state)
sub spectatefree_command {
	if (&flood_protection('spectatefree', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("scr_spectatefree 1");
		&rcon_command("say Free-spectate mode was ^2ENABLED ^7by an admin");
		&log_to_file('logs/admin.log', "!SPECTATEFREE: the specate-free mode was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("scr_spectatefree 0");
		&rcon_command("say Free-spectate mode was ^1DISABLED ^7by an admin");
		&log_to_file('logs/admin.log', "!SPECTATEFREE: the specate-free mode was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !spectatefree: $state, use on or off");
	}
}

# END: spectatefree

# BEGIN: !speed($speed)
sub speed_command {
	if (&flood_protection('speed', 30, $slot)) { return 1; }
	my $speed = shift;
	if ($speed =~ /^\d+$/) {
		&rcon_command("g_speed $speed");
		&rcon_command("say Speed has been set to: ^2$speed");
		&log_to_file('logs/admin.log', "!SPEED: speed was set to $speed by: $name - GUID $guid");
	}
	else {
		$temporary = &rcon_query("g_speed");
		if ($temporary =~ /\"g_speed\" is: \"(\d+)\^7\"/m) {
			$speed = $1;
			&rcon_command("say Speed is currently set to: ^2$speed");
		}
		else {
			&rcon_command("say Unfortunately, speed value has not been changed");
		}
	}
}

# END: speed

# BEGIN: !gravity($gravity)
sub gravity_command {
	if (&flood_protection('gravity', 30, $slot)) { return 1; }
	my $gravity = shift;
	if ($gravity =~ /^\d+$/) {
		&rcon_command("g_gravity $gravity");
		&rcon_command("say Gravity has been set to: ^1$gravity");
		&log_to_file('logs/admin.log', "!GRAVITY: gravity was set to $gravity by: $name - GUID $guid");
	}
	else {
		$temporary = &rcon_query("g_gravity");
		if ($temporary =~ /\"g_gravity\" is: \"(\d+)\^7\"/m) {
			$gravity = $1;
			&rcon_command("say Gravity is currently set to: ^1$gravity");
		}
		else {
			&rcon_command("say Unfortunately, gravity value has not been changed");
		}
	}
}

# END: gravity

# BEGIN: !glitch($state)
sub glitch_command {
	if (&flood_protection('glitch', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("say Glitch Server Mode Enabled. ^1NO KILLING NOW!");
		$config->{'glitch_server_mode'} = 1;
		&log_to_file('logs/admin.log', "!GLITCH: glitch mode was enabled by: $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("say Glitch Server Mode Disabled. ^2KILLING ARE ALLOWED NOW!");
		$config->{'glitch_server_mode'} = 0;
		&log_to_file('logs/admin.log', "!GLITCH: glitch mode was disabled by: $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !glitch: $state, use on or off");
	}
}

# END: glitch

# BEGIN: !yes(vote)
sub yes {
	if (&flood_protection('yes', 30, $slot)) { return 1; }
	my $slot = shift;
	my $name = shift;
	if (($vote_started) and (!$voted_by_slot{$slot})) {
		$voted_by_slot{$slot} = 1;
		$voted_yes++;
		if (($required_yes - $voted_yes) != 0) {
			&rcon_command("say $name ^7voted ^2YES^7, ^2YES ^7needed to pass:^2 " . ($required_yes - $voted_yes));
		}
	}
}

# END: yes

# BEGIN: !no(vote)
sub no {
	if (&flood_protection('no', 30, $slot)) { return 1; }
	my $slot = shift;
	my $name = shift;
	if (($vote_started) and (!$voted_by_slot{$slot})) {
		$voted_by_slot{$slot} = 1;
		$voted_no++;
		&rcon_command("say $name ^7voted ^1NO");
	}
}

# END: no

# BEGIN: !best
sub best {
	if (   (&flood_protection('best', 300))
		or (&flood_protection('worst', 300)))
	{
		return 1;
	}
	my $counter = 1;
	my @row;
	&rcon_command("say ^2Best ^7players of the server:");
	sleep 1;

	# Most Kills
	$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE kills > 0 ORDER BY kills DESC LIMIT 5;");
	$stats_sth->execute
	  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say ^2Most kills^7:");
	sleep 1;

	while (@row = $stats_sth->fetchrow_array) {
		&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with ^2$row[2] ^7kills");
		sleep 1;
	}

	# Best Kill to Death ratio
	$counter = 1;
	sleep 1;
	$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE kills > 100 ORDER BY (kills * 10000 / deaths) DESC LIMIT 5;");
	$stats_sth->execute
	  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say ^2Best k/d ratio^7:");
	sleep 1;

	while (@row = $stats_sth->fetchrow_array) {
		&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with^8 " . (int($row[2] / $row[3] * 100) / 100) . " ^7k/d ratio");
		sleep 1;
	}

	# Best Headshot Percentages
	$counter = 1;
	sleep 1;
	$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE kills > 100 ORDER BY (headshots * 10000 / kills) DESC LIMIT 5;");
	$stats_sth->execute
	  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say ^2Best headshot percentage^7:");
	sleep 1;

	while (@row = $stats_sth->fetchrow_array) {
		&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with^3 " . (int($row[4] / $row[2] * 10000) / 100) . " ^7headshot percentage");
		sleep 1;
	}
	if ($config->{'killing_sprees'}) {

		# Best Kill Spree
		$counter = 1;
		sleep 1;
		$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE best_killspree > 2 ORDER BY best_killspree DESC LIMIT 5;");
		$stats_sth->execute
		  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		&rcon_command("say ^2Best killing spree^7:");
		sleep 1;

		while (@row = $stats_sth->fetchrow_array) {
			&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with ^6$row[12] ^7kills in a row");
			sleep 1;
		}
	}
	if ($config->{'nice_shots'}) {

		# Best Nice Shots count
		$counter = 1;
		sleep 1;
		$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE nice_shots > 0 ORDER BY nice_shots DESC LIMIT 5;");
		$stats_sth->execute
		  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		&rcon_command("say ^2Most nice shot calls^7:");
		sleep 1;

		while (@row = $stats_sth->fetchrow_array) {
			&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with ^2$row[13] ^7nice shot calls");
			sleep 1;
		}
	}
	if ($gametype eq 'sd') {

		# Best Bomb Plants
		$counter = 1;
		sleep 1;
		$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE bomb_plants > 0 ORDER BY bomb_plants DESC LIMIT 5;");
		$stats_sth->execute
		  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		&rcon_command("say ^2Most bomb plants^7:");
		sleep 1;

		while (@row = $stats_sth->fetchrow_array) {
			&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with ^4$row[16] ^7planted bombs");
			sleep 1;
		}

		# Best Bomb Defuses
		$counter = 1;
		sleep 1;
		$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE bomb_defuses > 0 ORDER BY bomb_defuses DESC LIMIT 5;");
		$stats_sth->execute
		  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		&rcon_command("say ^2Most bomb defuses^7:");
		sleep 1;

		while (@row = $stats_sth->fetchrow_array) {
			&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with ^5$row[17] ^7bomb defuses");
			sleep 1;
		}
	}
}

# END: best

# BEGIN: get_name_by_guid($guid)
sub get_name_by_guid {
	my $guid = shift;
	my @row;
	$guid_to_name_sth = $guid_to_name_dbh->prepare("SELECT name FROM guid_to_name WHERE guid=? ORDER BY id DESC LIMIT 1");
	$guid_to_name_sth->execute($guid)
	  or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
	@row = $guid_to_name_sth->fetchrow_array;
	if    (!$row[0])              { return "^3$guid"; }
	elsif ($row[0] =~ /\^\^\d\d/) { return &strip_color($row[0]); }
	else                          { return $row[0]; }
}

# END: get_name_by_guid

# BEGIN: change_map
sub change_map {
	my $map = shift;
	if (!defined($map)) {
		print "WARNING: change_map was called without a map\n";
		return 1;
	}
	$map = lc $map;
	if (&flood_protection('change_map', 30, $slot)) { return 1; }
	&rcon_command("say ^2Changing to^7: ^3" . &description($map));
	$temporary = &rcon_query("map $map");

	if ($temporary =~ /Can't find map maps\/mp\/(\w+).d3dbsp/mi) {
		&rcon_command("say The server doesn't have that map (^2$1^7)");
		if (&flood_protection('vote', 1)) { return 1; }    # Reset the 'vote' flood protection
		return 1;
	}
	else { &log_to_file('logs/commands.log', "$name changed map to: $map"); }
}

# END: change_map

# BEGIN: change_gametype
sub change_gametype {
	my $gametype = shift;
	if (!defined($gametype)) {
		print "WARNING: change_gametype was called without a game type\n";
		return 1;
	}
	if ($gametype !~ /^(dm|tdm|ctf|hq|sd)$/) {
		print "WARNING: change_gametype was called with an invalid game_type: $gametype\n";
		return 1;
	}
	if (&flood_protection('change_gametype', 30, $slot)) { return 1; }
	&rcon_command("say ^2Changing gametype to^7: ^3" . &description($gametype));
	&rcon_command("g_gametype $gametype");
	&rcon_command("map_restart");
	&log_to_file('logs/commands.log', "$name changed gametype to: $gametype");
}

# END: change_gametype

# BEGIN: next_map_prediction
sub next_map_prediction {
	$temporary = &rcon_query('sv_mapRotationCurrent');
	if ($temporary =~ /\"sv_mapRotationCurrent\"\s+is:\s+\"\s*gametype\s+(\w+)\s+map\s+(\w+)/mi) {
		$next_gametype = $1;
		$next_map      = $2;
		print "Next Map: " . &description($next_map) . " and Next Gametype: " . &description($next_gametype) . "\n";
		$freshen_next_map_prediction = 0;
		return 1;
	}
	$temporary = &rcon_query('sv_mapRotation');
	if ($temporary =~ /\"sv_mapRotation\"\s+is:\s+\"\s*gametype\s+(\w+)\s+map\s+(\w+)/mi) {
		$next_gametype = $1;
		$next_map      = $2;
		print "Next Map: " . &description($next_map) . " and Next Gametype: " . &description($next_gametype) . "\n";
		$freshen_next_map_prediction = 0;
		return 1;
	}
	else {
		$next_gametype = $gametype;
		$next_map      = $mapname;
		print "Next Map: " . &description($next_map) . " and Next Gametype: " . &description($next_gametype) . "\n";
		$freshen_next_map_prediction = 0;
		return 1;
	}
}

# END: next_map_prediction

# BEGIN: check_player_names
sub check_player_names {
	print "Checking for bad names...\n";
	my $match_string;
	my $warned;
	foreach $slot (sort { $a <=> $b } keys %name_by_slot) {
		$warned = 0;
		foreach $match_string (@banned_names) {
			if ($name_by_slot{$slot} =~ /$match_string/) {
				$warned = 1;
				if (!defined($name_warn_level{$slot})) {
					$name_warn_level{$slot} = 0;
				}
				if ($name_warn_level{$slot} == 0) {
					print "NAME_WARN1: $name_by_slot{$slot} is using a banned name. Match: $match_string\n";
					&rcon_command("say $name_by_slot{$slot}^7: " . $config->{'banned_name_warn_message_1'});
					$name_warn_level{$slot} = 1;
				}
				elsif ($name_warn_level{$slot} == 1) {
					print "NAME_WARN2: $name_by_slot{$slot} is using a banned name. (2nd warning) Match: $match_string\n";
					&rcon_command("say $name_by_slot{$slot}^7: " . $config->{'banned_name_warn_message_2'});
					$name_warn_level{$slot} = 2;
				}
				elsif ($name_warn_level{$slot} == 2) {
					print "NAME_KICK: $name_by_slot{$slot} is using a banned name. (3rd strike) Match: $match_string\n";
					&rcon_command("say $name_by_slot{$slot}^7: " . $config->{'banned_name_kick_message'});
					sleep 1;
					&rcon_command("clientkick $slot");
					&log_to_file('logs/kick.log', "BANNED NAME: $name_by_slot{$slot} was kicked for having a banned name:  Match: $match_string");
				}
			}
		}
		if ((!defined($name_warn_level{$slot})) or (!$warned)) {
			$name_warn_level{$slot} = 0;
		}
	}
}

# END: check_player_names

# BEGIN: make_announcement
sub make_announcement {
	my $message = $announcements[int(rand($#announcements + 1))];
	print "Making Announcement: $message\n";
	&rcon_command("say $message");
}

# END: make_announcement

# BEGIN: !names(search_string);
sub names {
	my $search_string = shift;
	my @matches       = &matching_users($search_string);
	my @names;
	my @row;
	my $guessed = 0;

	if ($#matches == -1) {
		if (&flood_protection('names-nomatch', 10, $slot)) { return 1; }
		&rcon_command("say No matches for: $search_string");
	}
	elsif ($#matches == 0) {
		&log_to_file('logs/commands.log', "$name executed an !names search for $name_by_slot{$matches[0]}");
		if ($guid_by_slot{$matches[0]} > 0) {
			$guid_to_name_sth = $guid_to_name_dbh->prepare("SELECT name FROM guid_to_name WHERE guid=? ORDER BY id DESC LIMIT 100;");
			$guid_to_name_sth->execute($guid_by_slot{$matches[0]})
			  or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
			while (@row = $guid_to_name_sth->fetchrow_array) {
				push @names, $row[0];
			}
		}
		$ip = $ip_by_slot{$matches[0]};
		if ($ip =~ /\?$/) {
			$ip =~ s/\?$//;
			$guessed = 1;
		}
		if ($ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
			$ip_to_name_sth = $ip_to_name_dbh->prepare("SELECT name FROM ip_to_name WHERE ip=? ORDER BY id DESC LIMIT 100;");
			$ip_to_name_sth->execute($ip)
			  or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
			while (@row = $ip_to_name_sth->fetchrow_array) {
				push @names, $row[0];
			}
		}
		if ($#names == -1) {
			if (&flood_protection('names-none', 10, $slot)) { return 1; }
			&rcon_command("say No names found for: $name_by_slot{$matches[0]}");
		}
		else {
			# Remove the duplicates from the @names hash, and strip the less colorful versions of names.
			my $name;
			my $key;
			my %name_hash;

			foreach $name (@names) {
				if (!defined($name_hash{$name})) {

					# The name is not defined, consider adding it.
					# possibilities:
					#  1) it's a name that has more colors than what is already in the list
					if (defined($name_hash{&strip_color($name)})) {

						# This is a more colorful version of something already in the list.
						# Toast the old name.
						delete $name_hash{&strip_color($name)};

						# Add the new one
						$name_hash{$name} = 1;
					}

					#  2) it's not present in any form in the list.
					# (or may be a less colorful version of what is already in the list.
					else { $name_hash{$name} = 1; }

					# 3) it's a name that has less colors than what is already in the list
					# Also delete names that have only color codes in them
					foreach $key (keys %name_hash) {
						if (   $name ne $key and $name eq &strip_color($key)
							or $name =~ /^\^\^\d\d$/
							or $name =~ /^\^\d\s*$/
							or $name =~ /^\^\^\d\d[\d\^\s]*$/)
						{
							# Then we know that the name is a less colorful version of what is already in the list.
							delete $name_hash{$name};
							last;
						}
					}
				}
			}

			# finally, announce the list.
			my $found_none    = 1;
			my @announce_list = keys %name_hash;
			if (&flood_protection('names', 30, $slot)) { return 1; }
			foreach $key (@announce_list) {

				if ($name_by_slot{$matches[0]} ne $key) {
					if ($guessed) {
						&rcon_command("say $name_by_slot{$matches[0]} ^7proably also known as: $key");
					}
					else {
						&rcon_command("say $name_by_slot{$matches[0]} ^7also known as: $key");
					}
					$found_none = 0;
				}
			}
			if ($found_none) {
				&rcon_command("say No names found for $name_by_slot{$matches[0]}");
			}
		}
	}
	elsif ($#matches > 0) {
		&rcon_command("say Too many matches for: $search_string");
	}
}

# END: names

# BEGIN: !worst
sub worst {
	if (   (&flood_protection('worst', 300))
		or (&flood_protection('best', 300)))
	{
		return 1;
	}
	&rcon_command("say ^1Worst ^7players of the server:");
	my $counter = 1;
	my @row;
	sleep 1;

	# Most deaths
	$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE deaths > 0 ORDER BY deaths DESC LIMIT 5;");
	$stats_sth->execute
	  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say ^1Most deaths^7:");
	sleep 1;

	while (@row = $stats_sth->fetchrow_array) {
		&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with ^1$row[3] ^7deaths");
		sleep 1;
	}

	# Worst k2d ratio
	$counter = 1;
	sleep 1;
	$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE ((kills > 100) and (deaths > 50)) ORDER BY (kills * 10000 / deaths) ASC LIMIT 5;");
	$stats_sth->execute
	  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say ^1Worst k/d ratio^7:");
	sleep 1;

	while (@row = $stats_sth->fetchrow_array) {
		&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with^8 " . (int($row[2] / $row[3] * 100) / 100) . " ^7k/d ratio");
		sleep 1;
	}

	# Worst headshot percentages
	$counter = 1;
	sleep 1;
	$stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE ((kills > 100) and (headshots > 10)) ORDER BY (headshots * 10000 / kills) ASC LIMIT 5;");
	$stats_sth->execute
	  or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say ^1Worst headshot percentage^7:");
	sleep 1;

	while (@row = $stats_sth->fetchrow_array) {
		&rcon_command("say ^3" . ($counter++) . " ^7place: " . &get_name_by_guid($row[1]) . " ^7with^3 " . (int($row[4] / $row[2] * 10000) / 100) . " ^7headshot percentage");
		sleep 1;
	}
}

# END: !worst

# BEGIN: guid_sanity_check($guid,$ip)
sub guid_sanity_check {
	my $should_be_guid = shift;
	my $ip             = shift;
	$last_guid_sanity_check = $time;

	# make sure that the GUID sanity check is enabled before proceeding.
	if   ($config->{'guid_sanity_check'}) { }
	else                                  { return 0; }
	print "Running GUID sanity check\n";
	&log_to_file('logs/sanity.log', "Running GUID sanity check");

	# check to make sure that IP -> GUID = last guid
	print "Look Up GUID for $ip and make sure it's $should_be_guid\n";
	&log_to_file('logs/sanity.log', "Look Up GUID for $ip and make sure it's $should_be_guid");

	# if guid is nonzero and is not last_guid, then we know sanity fails.
	my $total_tries       = 3;                             # The total number of attempts to get an answer out of activision.
	my $read_timeout      = 1;                             # Number of seconds to wait for activison to respond to a packet.
	my $activision_master = 'cod2master.activision.com';
	my $port              = 20700;
	my $d_ip;
	my $message;
	my $current_try   = 0;
	my $still_waiting = 1;
	my $got_response  = 0;
	my $portaddr;
	print "\nAsking $activision_master if $ip has provided a valid CD-KEY recently.\n\n";
	&log_to_file('logs/sanity.log', "Asking $activision_master if $ip has provided a valid CD-KEY recently.");
	socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp"))
	  or &die_nice("Socket error: $!");
	my $random       = int(rand(7654321));
	my $send_message = "\xFF\xFF\xFF\xFFgetIpAuthorize $random $ip 0";
	$d_ip = gethostbyname($activision_master);
	my $selecta = IO::Select->new;
	$selecta->add(\*SOCKET);
	my @ready;

	while (($current_try < $total_tries) and ($still_waiting)) {
		$current_try++;

		# Send the packet
		$portaddr = sockaddr_in($port, $d_ip);
		send(SOCKET, $send_message, 0, $portaddr) == length($send_message)
		  or &die_nice("Cannot send to $activision_master($port): $!\n\n");

		# Check to see if there is a response yet.
		@ready = $selecta->can_read($read_timeout);
		if (defined($ready[0])) {

			# Yes, the socket is ready.
			$portaddr = recv(SOCKET, $message, $maximum_length, 0)
			  or &die_nice("Socket error: recv: $!");

			# strip the 4 \xFF bytes at the begining.
			$message =~ s/^.{4}//;
			$got_response  = 1;
			$still_waiting = 0;
		}
	}
	if ($got_response) {
		if ($message =~ /ipAuthorize ([\d\-]+) ([a-z]+) (\w+) (\d+)/) {
			my ($session_id, $result, $reason, $guid) = ($1, $2, $3, $4);
			print "RESULTS:\n";
			print "\tIP Address: $ip\n";
			print "\tAction: $result\n";
			print "\tReason: $reason\n";
			print "\tGUID: $guid\n";
			print "\n";

			if ($reason eq 'CLIENT_UNKNOWN_TO_AUTH') {
				print "Explaination of: $reason\n";
				print "\tThis IP Address has not provided any CD Keys to the activision server\n";
				print "\tThis IP Address may not playing COD2 currently, or\n";
				print "\tActivision has not heard a key from this IP recently.\n";
				&log_to_file('logs/sanity.log', "RESULTS: $reason");
			}
			if ($reason eq 'BANNED_CDKEY') {
				print "Explaination of: $reason\n";
				print "\tThis IP Address is using a well known stolen CD Key.\n";
				print "\tActivision has BANNED this CD Key and will not allow anyone to use it.\n";
				print "\tThis IP address is using a stolen copy of CoD2\n\n";
				&log_to_file('logs/sanity.log', "RESULTS: $reason");
			}
			if ($reason eq 'INVALID_CDKEY') {
				print "Explaination of: $reason\n";
				print "\tThis IP Address is trying to use the same CD Key from multiple IPs.\n";
				print "\tActivision has already seen this Key recently used by a different IP.\n";
				print "\tThis is a valid CD Key, but is being used from multiple locations\n";
				print "\tActivision only allows one IP per key.\n\n";
				&log_to_file('logs/sanity.log', "RESULTS: $reason");
			}

			# Now, check to make sure our GUID numbers match up.
			if ($guid) {
				if ($guid == $should_be_guid) {
					print "\nOK: GUID Sanity check: PASSED\n\n";
					&log_to_file('logs/sanity.log', "GUID Sanity check: PASSED: GUID $guid == $should_be_guid");
				}
				else {
					&rcon_command("say ^1WARNING^7: GUID Sanity check failed for $name_by_slot{$most_recent_slot}");
					print "\nFAIL: GUID Sanity check: FAILED\n";
					print "\tIP: $ip was supposed to be GUID $should_be_guid but came back as $guid\n\n";
					&log_to_file('logs/sanity.log', "SANITY FAILED: $name_by_slot{$most_recent_slot}  IP: $ip was supposed to be GUID $should_be_guid but came back as $guid - Server has been up for: $uptime");
				}
			}
		}
		else {
			print "\nERROR:\n\tGot a response, but not in the format expected\n";
			print "\t$message\n\n";
			&log_to_file('logs/sanity.log', "WARNING: Got a response, but not in the format expected: $message");
		}
	}
	else {
		print "\nERROR:\n\t$activision_master is not currently responding to requests.\n";
		print "\n\tSorry.  Try again later.\n\n";
		&log_to_file('logs/sanity.log', "WARNING: $activision_master is not currently responding to requests.");
	}
	$most_recent_guid = 0;
	$most_recent_slot = 0;
}

# END: guid_sanity_check

# BEGIN: flood_protection($attribute,$interval,$slot)
sub flood_protection {
	my $attribute    = shift;
	my $min_interval = shift;
	my $slot         = shift;

	# Make sure that flood protection is enabled. Otherwise, all is allowed.
	if   ($config->{'flood_protection'}) { }
	else                                 { return 0; }

	# Exemption for global admins (1 second delay)
	if (&check_access('flood_exemption')) { $min_interval = 1; }

	# Ensure that all values are defined.
	if ((!defined($min_interval)) or ($min_interval !~ /^\d+$/)) {
		$min_interval = 30;
	}
	if ((!defined($slot)) or ($slot !~ /^\d+$/)) { $slot = 'global'; }
	my $key = $attribute . '.' . $slot;
	if (!defined($flood_protection{$key})) {
		$flood_protection{$key} = 0;
	}

	if ($time >= $flood_protection{$key}) {

		# The command is allowed
		$flood_protection{$key} = $time + $min_interval;
		return 0;
	}
	else {
		# Too soon,  flood protection triggured.
		print "Flood protection activated.  '$attribute' command not allowed to be run again yet.\n";
		print "\tNot allowed to run for another  " . &duration(($flood_protection{$key} - $time)) . "\n";
		&log_to_file('logs/flood_protect.log', "Denied command access to $name for $attribute.  Not allowed to run for another  " . &duration(($flood_protection{$key} - $time)));
		return 1;
	}
}

# END: flood_protection

# BEGIN: !tell($search_string,$message)
sub tell {
	my $search_string = shift;
	my $message       = shift;
	my $key;
	if ((!defined($search_string)) or ($search_string !~ /./)) {
		return 1;
	}
	if ((!defined($message)) or ($message !~ /./)) { return 1; }
	my @matches = &matching_users($search_string);
	if ($#matches == -1) {
		if (&flood_protection('tell-nomatch', 10, $slot)) { return 1; }
		&rcon_command("say No matches for: $search_string");
	}
	else {
		if (&flood_protection('tell', 30, $slot)) { return 1; }
		foreach $key (@matches) {
			&rcon_command("say $name_by_slot{$key}^7: $message");
		}
	}
}

# END: tell

# BEGIN: !lastbans($number);
sub last_bans {
	my $number = shift;
	my @row;
	if ($number < 0) { $number = 1; }
	$number = int($number);
	if (&flood_protection('lastbans', 30, $slot)) { return 1; }
	$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE unban_time > $time ORDER BY id DESC LIMIT $number");
	$bans_sth->execute or &die_nice("Unable to do select recent bans\n");

	while (@row = $bans_sth->fetchrow_array) {
		&rcon_command("say $row[5] ^7was banned " . &duration($time - $row[1]) . " ago (BAN ID#: ^1$row[0]^7, IP - ^2$row[3]^7, GUID - ^3$row[4]^7)");
		sleep 1;
	}
}

# END: lastbans

# BEGIN: dictionary
sub dictionary {
	my $word = shift;
	my @lines;
	my @definitions;
	my $definition;
	my $term;
	my $content;
	my $counter = 0;
	my @row;

	if (!defined($word)) {
		&rcon_command("say !define what?");
		return 1;
	}

	# If we are being asked to define a word, define it and return
	if ($word =~ /(.*)\s+=\s+(.*)/) {
		($term, $definition) = ($1, $2);
		$term =~ s/\s*$//;
		if (&check_access('define')) {
			$definitions_sth = $definitions_dbh->prepare("INSERT INTO definitions VALUES (NULL, ?, ?)");
			$definitions_sth->execute($term, $definition)
			  or &die_nice("Unable to do insert\n");
			&rcon_command("say ^2Added definition for: ^1$term");
			return 1;
		}
	}

	# Now, Most imporant are the definitions that have been manually defined.
	# They come first.
	$definitions_sth = $definitions_dbh->prepare("SELECT definition FROM definitions WHERE term=?;");
	$definitions_sth->execute($word)
	  or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
	while (@row = $definitions_sth->fetchrow_array) {
		print "DATABASE DEFINITION: $row[0]\n";
		$counter++;

		# 8 definitions max by default
		if ($#definitions < 8) {
			push(@definitions, "^$counter$counter^7) ^2 $row[0]");
		}
	}

	# Now we sanatize what we're looking for - online databases don't have multiword definitions.
	if ($word =~ /[^A-Za-z\-\_\s\d]/) {
		&rcon_command("say $name^7: Invalid syntax, use !define = word to add it's definition to database");
		sleep 1;
		&rcon_command("say $name^7: Or !define word to display results from online-dictonary - WordNet");
		return 1;
	}
	$content = get("http://wordnetweb.princeton.edu/perl/webwn?s=" . $word);
	if (!defined($content)) {
		&rcon_command("say WordNet is not available at this time, try again later");
		return 1;
	}
	@lines = split(/\n+/, $content);
	foreach (@lines) {
		if (/<\s*b>$word<\/b>[^\(]+\(([^\)]*)\)/) {
			$definition = $1;
			print "ONLINE DEFINITION: $1\n";
			$counter++;

			# 8 definitions max by default
			if ($#definitions < 8) {
				push(@definitions, "^$counter$counter^7) ^2$definition");
			}
		}
	}
	if (!$counter) {
		&rcon_command("say Unfortunately, no definitions found for: ^2$word");
	}
	else {
		if ($counter == 1) {
			&rcon_command("say ^3One ^7definition found for: ^2$word");
		}
		else {
			&rcon_command("say ^3$counter ^7definitions found for: ^2$word");
		}
		sleep 1;
		foreach $definition (@definitions) {
			&rcon_command("say $definition");
			sleep 1;
		}
	}
}

# END: dictionary

# BEGIN: check_guid_zero_players
sub check_guid_zero_players {
	my @possible;
	print "GUID ZERO audit in progress...\n";
	&log_to_file('logs/audit.log', "GUID ZERO audit in progress...");
	foreach $slot (keys %guid_by_slot) {

		if (    (defined($guid_by_slot{$slot}))
			and (defined($ip_by_slot{$slot}))
			and ($guid_by_slot{$slot} == 0)
			and ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/))
		{
			push @possible, $slot;
		}
	}
	if ($#possible == -1) {
		print "GUID Zero Audit: PASSED, there are no GUID zero players.\n";
		&log_to_file('logs/audit.log', "GUID Zero Audit: PASSED, there are no GUID zero players.");
		return 1;
	}
	&fisher_yates_shuffle(\@possible);
	my $total_tries       = 3;                             # The total number of attempts to get an answer out of activision.
	my $read_timeout      = 1;                             # Number of seconds to wait for activison to respond to a packet.
	my $activision_master = 'cod2master.activision.com';
	my $port              = 20700;
	my $ip_address;
	my $d_ip = gethostbyname($activision_master);
	my $message;
	my $current_try   = 0;
	my $still_waiting = 1;
	my $got_response  = 0;
	my $portaddr;
	my $random = int(rand(7654321));
	my $send_message;
	my $selecta;
	my @ready;
	my $kick_reason;
	my $dirtbag;

	# Try as many as we can within our time limit
	foreach $slot (@possible) {
		$send_message = "\xFF\xFF\xFF\xFFgetIpAuthorize $random $ip_by_slot{$slot} 0";
		print "AUDITING: slot: $slot IP: $ip_by_slot{$slot} GUID: $guid_by_slot{$slot} NAME: $name_by_slot{$slot}\n";
		&log_to_file('logs/audit.log', "AUDITING: slot: $slot IP: $ip_by_slot{$slot} GUID: $guid_by_slot{$slot} NAME: $name_by_slot{$slot}");
		print "\nAsking $activision_master if $ip_by_slot{$slot} has provided a valid CD-KEY recently.\n\n";
		&log_to_file('logs/audit.log', "Asking $activision_master if $ip_by_slot{$slot} has provided a valid CD-KEY recently.");
		socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp"))
		  or &die_nice("Socket error: $!");
		$selecta = IO::Select->new;
		$selecta->add(\*SOCKET);

		while (($current_try < $total_tries) and ($still_waiting)) {
			$current_try++;

			# Send the packet
			$portaddr = sockaddr_in($port, $d_ip);
			send(SOCKET, $send_message, 0, $portaddr) == length($send_message)
			  or &die_nice("cannot send to $activision_master($port): $!\n\n");

			# Check to see if there is a response yet.
			@ready = $selecta->can_read($read_timeout);
			if (defined($ready[0])) {

				# Yes, the socket is ready.
				$portaddr = recv(SOCKET, $message, $maximum_length, 0)
				  or &die_nice("Socket error: recv: $!");

				# strip the 4 \xFF bytes at the begining.
				$message =~ s/^.{4}//;
				$got_response  = 1;
				$still_waiting = 0;
			}
		}
		if ($got_response) {
			if ($message =~ /ipAuthorize ([\d\-]+) ([a-z]+) (\w+) (\d+)/) {
				my ($session_id, $result, $reason, $guid) = ($1, $2, $3, $4);
				print "RESULTS:\n";
				print "\tIP Address: $ip_by_slot{$slot}\n";
				print "\tAction: $result\n";
				print "\tReason: $reason\n";
				print "\tGUID: $guid\n";
				print "\n";
				$dirtbag = 0;

				if ($reason eq 'CLIENT_UNKNOWN_TO_AUTH') {
					print "Explaination of: $reason\n";
					print "\tThis IP Address has not provided any CD Keys to the activision server\n";
					print "\tThis IP Address may not playing COD2 currently, or\n";
					print "\tActivision has not heard a key from this IP recently.\n";
					&log_to_file('logs/audit.log', "RESULTS: $reason");
				}
				if ($reason eq 'BANNED_CDKEY') {
					print "Explaination of: $reason\n";
					print "\tThis IP Address is using a well known stolen CD Key.\n";
					print "\tActivision has BANNED this CD Key and will not allow anyone to use it.\n";
					print "\tThis IP address is using a stolen copy of CoD2\n\n";
					&log_to_file('logs/audit.log', "RESULTS: $reason");
					$dirtbag     = 1;
					$kick_reason = "was kicked for using a banned CD-KEY";
				}
				if ($reason eq 'INVALID_CDKEY') {
					print "Explaination of: $reason\n";
					print "\tThis IP Address is trying to use the same CD Key from multiple IPs.\n";
					print "\tActivision has already seen this Key recently used by a different IP.\n";
					print "\tThis is a valid CD Key, but is being used from multiple locations\n";
					print "\tActivision only allows one IP per key.\n\n";
					&log_to_file('logs/audit.log', "RESULTS: $reason");
					$dirtbag     = 1;
					$kick_reason = "was kicked for using an invalid CD-KEY. Perhaps this CD-KEY is already in use";
				}
				if (($dirtbag) and ($reason eq 'BANNED_CDKEY')) {
					&rcon_command("say $name_by_slot{$slot} ^7$kick_reason");
					sleep 1;
					&rcon_command("clientkick $slot");
					&log_to_file('logs/kick.log', "CD-KEY: $name_by_slot{$slot} was kicked for: $kick_reason");
					my $ban_name   = 'unknown';
					my $ban_ip     = 'unknown';
					my $ban_guid   = 0;
					my $unban_time = $time + 28800;

					if ($name_by_slot{$slot}) {
						$ban_name = $name_by_slot{$slot};
					}
					if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
						$ban_ip = $ip_by_slot{$slot};
					}
					if ($guid_by_slot{$slot}) {
						$ban_guid = $guid_by_slot{$slot};
					}
					$bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
					$bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name)
					  or &die_nice("Unable to do insert\n");
					$ban_message_spam = $time + 3;    # 3 seconds spam protection
				}
			}
			else {
				print "\nERROR:\n\tGot a response, but not in the format expected\n";
				print "\t$message\n\n";
				&log_to_file('logs/audit.log', "WARNING: Got a response, but not in the format expected: $message");
			}
		}
		else {
			print "\nERROR:\n\t$activision_master is not currently responding to requests.\n";
			print "\n\tSorry.  Try again later.\n\n";
			&log_to_file('logs/audit.log', "WARNING: $activision_master is not currently responding to requests.");
		}
	}
}

# END: check_guid_zero_players

sub fisher_yates_shuffle {
	my $array = shift;
	my $i;
	for ($i = @$array; --$i;) {
		my $j = int rand($i + 1);
		next if $i == $j;
		@$array[$i, $j] = @$array[$j, $i];
	}
}

sub tan {
	sin($_[0]) / cos($_[0]);
}

sub random_pwd {
	my $length = shift;
	my @chars = (0 .. 9, 'a' .. 'z', 'A' .. 'Z');
	return join '', @chars[map rand @chars, 0 .. $length];
}

sub reset {
	foreach $reset_slot (keys %last_activity_by_slot) {
		$last_activity_by_slot{$reset_slot} = 'gone';
		$idle_warn_level{$reset_slot}       = 0;
		&update_name_by_slot('SLOT_EMPTY', $reset_slot);
		$ip_by_slot{$reset_slot}          = 'not_yet_known';
		$guid_by_slot{$reset_slot}        = 0;
		$spam_count{$reset_slot}          = 0;
		$spam_last_said{$reset_slot}      = &random_pwd(16);
		$ping_by_slot{$reset_slot}        = 0;
		$last_ping_by_slot{$reset_slot}   = 0;
		$penalty_points{$reset_slot}      = 0;
		$last_killed_by_name{$reset_slot} = 'none';
		$last_killed_by_guid{$reset_slot} = 0;
		$last_kill_by_name{$reset_slot}   = 'none';
		$last_kill_by_guid{$reset_slot}   = 0;
		$kill_spree{$reset_slot}          = 0;
		$best_spree{$reset_slot}          = 0;
		$ignore{$reset_slot}              = 0;
		$last_rconstatus                  = 0;
	}
}

sub ftp_connect {

	# initialize FTP connection here.
	fileparse_set_fstype;    # FTP uses UNIX rules
	$ftp_tmpFileName = tmpnam;
	$ftp_verbose and print "FTP $ftp_host\n";
	$ftp = Net::FTP->new($ftp_host, Timeout => 60)
	  or &die_nice("FTP: Cannot ftp to $ftp_host: $!");
	$ftp_verbose
	  and print "USER: " . $config->{'ftp_username'} . " \t PASSWORD: " . '*' x length($config->{'ftp_password'}) . "\n";    # hide password
	$ftp->login($config->{'ftp_username'}, $config->{'ftp_password'})
	  or &die_nice("FTP: Can't login to $ftp_host: $!");
	$ftp_verbose and print "CWD: $ftp_dirname\n";
	$ftp->cwd($ftp_dirname) or &die_nice("FTP: Can't cd  $!");

	if ($config->{'use_passive_ftp'}) {
		print "Using Passive ftp mode...\n\n";
		$ftp->pasv or &die_nice($ftp->message);
	}
	$ftp_lines and &ftp_getNlines;
	$ftp_type    = $ftp->binary;
	$ftp_lastEnd = $ftp->size($ftp_basename)
	  or &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n");
	$ftp_verbose and print "SIZE $ftp_basename: " . $ftp_lastEnd . " bytes\n\n";
}

sub ftp_getNlines {
	my $bytes = ($ftp_lines + 1) * 64;    # guess how many bytes we have to download to get N lines
	my $keepGoing;
	my @data;
	my $length;
	do {
		my $actualBytes = &ftp_getNchars($bytes);
		open(TEMPFILE, $ftp_tmpFileName)
		  or &die_nice("FTP: Could not open $ftp_tmpFileName");
		@data = <TEMPFILE>;
		close(TEMPFILE) and unlink($ftp_tmpFileName);
		$length    = $#data;
		$keepGoing = ($length <= $ftp_lines and $actualBytes == $bytes);    #we want to download one extra line (to avoid truncation)
		$bytes     = $bytes * 2;                                            # get more bytes this time. TODO: could calculate average line length and use that
	} while ($keepGoing);

	# just print the last N lines
	my $startLine = $length - $ftp_lines;
	if ($startLine < 0) { $startLine = 0; }
	for (my $i = $startLine + 1; $i <= $length; $i++) {
		push @ftp_buffer, $data[$i];
	}
	@ftp_buffer = reverse @ftp_buffer;
}

# get N bytes and store in tempfile, return number of bytes downloaded
sub ftp_getNchars {
	my ($bytes) = @_;
	my $type    = $ftp->binary;
	my $size    = $ftp->size($ftp_basename)
	  or &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n");
	my $startPos = $size - $bytes;

	if ($startPos < 0) {
		$startPos = 0;
		$bytes    = $size;
	}    #file is smaller than requested number of bytes
	-e $ftp_tmpFileName and &die_nice("FTP: $ftp_tmpFileName exists");
	$ftp_verbose and print "GET: $ftp_basename, $ftp_tmpFileName, $startPos\n";
	$ftp->get($ftp_basename, $ftp_tmpFileName, $startPos);
	return $bytes;
}

sub ftp_get_line {
	if (!defined($ftp_buffer[0])) {
		$ftp_type       = $ftp->binary;
		$ftp_currentEnd = $ftp->size($ftp_basename)
		  or &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n");
		if ($ftp_currentEnd > $ftp_lastEnd) {
			$ftp_verbose
			  and print "FTP: SIZE $ftp_basename increased: " . ($ftp_currentEnd - $ftp_lastEnd) . " bytes\n";
			$ftp_verbose
			  and print "FTP: GET: $ftp_basename, $ftp_tmpFileName, $ftp_lastEnd\n";
			-e $ftp_tmpFileName and &die_nice("FTP: $ftp_tmpFileName exists");
			while (!-e $ftp_tmpFileName) {
				$ftp->get($ftp_basename, $ftp_tmpFileName, $ftp_lastEnd);
			}
			open(TEMPFILE, $ftp_tmpFileName)
			  or &die_nice("FTP: Could not open $ftp_tmpFileName");
			while ($line = <TEMPFILE>) { push @ftp_buffer, $line; }
			close(TEMPFILE);
			unlink($ftp_tmpFileName);
			$ftp_lastEnd = $ftp_currentEnd;

			# we reverse the order so that lines pop out in chronological order
			@ftp_buffer = reverse @ftp_buffer;
		}
	}
	if (defined($ftp_buffer[0])) {
		$line = pop @ftp_buffer;
		return $line;
	}
	else { return undef; }
}

# BEGIN: toggle_weapon
sub toggle_weapon {
	my ($weapon, $requested_state) = (@_);
	if ($weapon eq "Smoke Grenades") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_smokegrenades 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_smokegrenades 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
	elsif ($weapon eq "Frag Grenades") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_fraggrenades 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_fraggrenades 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
	elsif ($weapon eq "Shotguns") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_shotgun 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_shotgun 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
	elsif ($weapon eq "Rifles") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_kar98k 1");
			&rcon_command("set scr_allow_enfield 1");
			&rcon_command("set scr_allow_nagant 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_kar98k 0");
			&rcon_command("set scr_allow_enfield 0");
			&rcon_command("set scr_allow_nagant 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
	elsif ($weapon eq "Semi-Rifles") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_m1carbine 1");
			&rcon_command("set scr_allow_m1garand 1");
			&rcon_command("set scr_allow_g43 1");
			&rcon_command("set scr_allow_svt40 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_m1carbine 0");
			&rcon_command("set scr_allow_m1garand 0");
			&rcon_command("set scr_allow_g43 0");
			&rcon_command("set scr_allow_svt40 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
	elsif ($weapon eq "Sniper Rifles") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_kar98ksniper 1");
			&rcon_command("set scr_allow_enfieldsniper 1");
			&rcon_command("set scr_allow_nagantsniper 1");
			&rcon_command("set scr_allow_springfield 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_kar98ksniper 0");
			&rcon_command("set scr_allow_enfieldsniper 0");
			&rcon_command("set scr_allow_nagantsniper 0");
			&rcon_command("set scr_allow_springfield 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
	elsif ($weapon eq "MachineGuns") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_bar 1");
			&rcon_command("set scr_allow_bren 1");
			&rcon_command("set scr_allow_mp44 1");
			&rcon_command("set scr_allow_ppsh 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_bar 0");
			&rcon_command("set scr_allow_bren 0");
			&rcon_command("set scr_allow_mp44 0");
			&rcon_command("set scr_allow_ppsh 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
	elsif ($weapon eq "SubMachineGuns") {
		if ($requested_state =~ /yes|1|on|enable/i) {
			&rcon_command("say Turning on ^3$weapon");
			&rcon_command("set scr_allow_sten 1");
			&rcon_command("set scr_allow_mp40 1");
			&rcon_command("set scr_allow_thompson 1");
			&rcon_command("set scr_allow_pps42 1");
			&rcon_command("set scr_allow_greasegun 1");
			&rcon_command("say ^3$weapon ^7was enabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was enabled by:  $name - GUID $guid");
		}
		elsif ($requested_state =~ /no|0|off|disable/i) {
			&rcon_command("say Turning off ^3$weapon");
			&rcon_command("set scr_allow_sten 0");
			&rcon_command("set scr_allow_mp40 0");
			&rcon_command("set scr_allow_thompson 0");
			&rcon_command("set scr_allow_pps42 0");
			&rcon_command("set scr_allow_greasegun 0");
			&rcon_command("say ^3$weapon ^7was disabled by an admin.");
			&log_to_file('logs/admin.log', "$weapon was disabled by:  $name - GUID $guid");
		}
	}
}

# END: toggle_weapon

# BEGIN: update_name_by_slot
sub update_name_by_slot {
	my $name = shift;
	my $slot = shift;
	if ((!defined($slot)) or ($slot !~ /^\-?\d+$/)) {
		&die_nice("invalid slot number passed to update_slot_by_name: $slot\n\n");
	}
	if (!defined($name)) {
		&die_nice("invalid name passed to update_slot_by_name: $name\n\n");
	}

	# strip trailing spaces from the name.
	$name =~ s/\s+$//;
	if ($name =~ /\^\^\d\d/) { $name = &strip_color($name); }

	if (!defined($name_by_slot{$slot})) {
		$name_by_slot{$slot} = $name;
	}

	if ($name_by_slot{$slot} ne $name) {
		if (    ($name_by_slot{$slot} ne 'SLOT_EMPTY')
			and ($name ne 'SLOT_EMPTY'))
		{
			if (    ($name_by_slot{$slot} ne &strip_color($name))
				and ((&strip_color($name_by_slot{$slot}) ne $name)))
			{
				print "NAME CHANGE: $name_by_slot{$slot} changed their name to: $name\n";

				# Detect Name Thieves
				if (    (defined($config->{'ban_name_thieves'}))
					and ($config->{'ban_name_thieves'}))
				{
					my $i;
					my $stripped_compare;
					my $stripped_old    = &strip_color($name_by_slot{$slot});
					my $stripped_new    = &strip_color($name);
					my $old_name_stolen = 0;
					my $new_name_stolen = 0;

					foreach $i (keys %name_by_slot) {
						if (    ($name_by_slot{$i} ne 'SLOT_EMPTY')
							and ($slot ne $i))
						{
							$stripped_compare = &strip_color($name_by_slot{$i});

							# Compare the old name for matches
							if ($name_by_slot{$slot} eq $name_by_slot{$i}) {
								$old_name_stolen = 1;
							}
							elsif ($name_by_slot{$slot} eq $stripped_compare) {
								$old_name_stolen = 1;
							}
							elsif ($stripped_old eq $name_by_slot{$i}) {
								$old_name_stolen = 1;
							}
							elsif ($stripped_old eq $stripped_compare) {
								$old_name_stolen = 1;
							}

							# Compare the new name for matches
							if ($name eq $name_by_slot{$i}) {
								$new_name_stolen = 1;
							}
							elsif ($name eq $stripped_compare) {
								$new_name_stolen = 1;
							}
							elsif ($stripped_new eq $name_by_slot{$i}) {
								$new_name_stolen = 1;
							}
							elsif ($stripped_new eq $stripped_compare) {
								$new_name_stolen = 1;
							}
						}
					}
					if (($old_name_stolen) and ($new_name_stolen)) {
						&rcon_command("say ^1NAME STEALING DETECTED^7: ^3Slot #^1$slot ^7was permanently banned for name stealing!");
						my $ban_name   = 'NAME STEALING JERKASS';
						my $ban_ip     = 'unknown';
						my $ban_guid   = 0;
						my $unban_time = 2125091758;

						if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
							$ban_ip = $ip_by_slot{$slot};
						}
						if ($guid_by_slot{$slot}) {
							$ban_guid = $guid_by_slot{$slot};
						}
						&rcon_command("clientkick $slot");
						&log_to_file('logs/kick.log', "BAN: NAME_THIEF: $ban_ip | $guid_by_slot{$slot} was permanently for being a name thief: $name | $name_by_slot{$slot}");
						$bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
						$bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name) or &die_nice("Unable to do insert\n");
						$ban_message_spam = $time + 3;    # 3 seconds spam protection
					}
				}

				# End of Name Thief Detection
			}
		}
		$name_by_slot{$slot} = $name;
	}
}

# END: update_name_by_slot

# /rcon scr_friendlyfire <0/1/2/3>  0 = friendly fire off, 1=friendly fire on, 2=reflect damage, 3=shared.
# BEGIN: !friendlyfire($state)
sub friendlyfire_command {
	if (&flood_protection('friendlyfire', 30, $slot)) { return 1; }
	my $state = shift;
	if ($state =~ /^(yes|1|on|enabled?)$/i) {
		&rcon_command("scr_friendlyfire 1");
		$friendly_fire = 1;
		&rcon_command("say Admin ^1ENABLED ^7Friendly fire. Be careful, try not to hurt your teammates");
		&log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED by:  $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
		&rcon_command("scr_friendlyfire 0");
		$friendly_fire = 0;
		&rcon_command("say Admin ^2DISABLED ^7Friendly fire");
		&log_to_file('logs/admin.log', "!friendlyfire: friendly fire was DISABLED by:  $name - GUID $guid");
	}
	elsif ($state =~ /^2$/i) {
		&rcon_command("scr_friendlyfire 2");
		$friendly_fire = 2;
		&rcon_command("say Admin ^1ENABLED ^7Friendly fire with reflect damage");
		&log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED with reflective team damage by:  $name - GUID $guid");
	}
	elsif ($state =~ /^3$/i) {
		&rcon_command("scr_friendlyfire 3");
		$friendly_fire = 3;
		&rcon_command("say Admin ^1ENABLED ^7Friendly fire with shared damage");
		&log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED with shared team damage by:  $name - GUID $guid");
	}
	else {
		&rcon_command("say Unknown state type for !friendlyfire. Possible values from 0 to 3");
	}
}

# END: friendlyfire

#BEGIN: make_affiliate_server_announcement
sub make_affiliate_server_announcement {
	my $server;
	my $hostname   = 'undefined';
	my $clients    = 0;
	my $gametype   = 'undefined';
	my $maxclients = 0;
	my $mapname    = 'undefined';
	my @info_lines;
	my @results;
	my $num_servers;

	foreach $server (@affiliate_servers) {
		$hostname   = 'undefined';
		$clients    = 0;
		$gametype   = 'undefined';
		$maxclients = 0;
		$mapname    = 'undefined';
		$line       = &get_server_info($server);
		$num_servers++;
		@info_lines = split(/\n/, $line);

		foreach $line (@info_lines) {
			$line =~ s/\s+$//;
			if ($line =~ /^hostname:\s+(.*)$/) {
				$hostname = $1;
				$servername_cache{$server} = $hostname;
			}
			if ($line =~ /^clients:\s+(\d+)$/) { $clients = $1; }
			if ($line =~ /^gametype:\s+(\w+)$/) {
				$gametype = $1;
				$gametype = &description($gametype);
			}
			if ($line =~ /^sv_maxclients:\s+(\d+)$/) { $maxclients = $1; }
			if ($line =~ /^mapname:\s+(\w+)$/) {
				$mapname = $1;
				$mapname = &description($mapname);
			}
		}
		if ($clients) {
			if ($clients == 1) {
				$line = "^1$clients ^7player at ^7$hostname^7 - ^2$mapname^7 | ^3$gametype\n";
				push @results, $line;
			}
			else {
				$line = "^1$clients ^7players at ^7$hostname^7 - ^2$mapname^7 | ^3$gametype\n";
				push @results, $line;
			}
		}
	}
	if (defined($results[0])) {
		if ($num_servers == 1) {
			&rcon_command("say It's time to check what's happening on other server:");
		}
		else {
			&rcon_command("say It's time to check what's happening on other servers:");
		}
		sleep 1;
		foreach $line (@results) {
			&rcon_command("say $line");
			if ($num_servers > 1) { sleep 1; }
		}
	}
}

# END: make_affiliate_server_announcement

# BEGIN: get_server_info($ip_address)
sub get_server_info {
	my $ip_address   = shift;
	my $total_tries  = 3;       # The total number of attempts to get an answer out of the server.
	my $read_timeout = 1;       # Number of seconds per attempt to wait for the response packet.
	my $port         = 28960;
	my $d_ip;
	my $message;
	my $current_try   = 0;
	my $still_waiting = 1;
	my $got_response  = 0;
	my $portaddr;
	my %infohash;
	my $return_text = '';

	if ($ip_address =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\:(\d{1,5})$/) {
		($ip_address, $port) = ($1, $2);
	}
	if (   (!defined($ip_address))
		or ($ip_address !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/))
	{
		return "IP Address format error";
	}
	socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp"))
	  or return "Socket error: $!";
	my $send_message = "\xFF\xFF\xFF\xFFgetinfo xxx";
	$d_ip = inet_aton($ip_address);
	my $selecta = IO::Select->new;
	$selecta->add(\*SOCKET);
	my @ready;

	while (($current_try < $total_tries) and ($still_waiting)) {
		$current_try++;

		# Send the packet
		$portaddr = sockaddr_in($port, $d_ip);
		send(SOCKET, $send_message, 0, $portaddr) == length($send_message)
		  or &die_nice("cannot send to $ip_address($port): $!\n\n");

		# Check to see if there is a response yet.
		@ready = $selecta->can_read($read_timeout);
		if (defined($ready[0])) {

			# Yes, the socket is ready.
			$portaddr = recv(SOCKET, $message, $maximum_length, 0)
			  or &die_nice("Socket error: recv: $!");

			# strip the 4 \xFF bytes at the begining.
			$message =~ s/^.{4}//;
			$got_response  = 1;
			$still_waiting = 0;
		}
	}
	if ($got_response) {
		if ($message =~ /infoResponse/) {
			$message = substr($message, 14, length($message));
			my @parts = split(/\\/, $message);
			my $value;
			while (@parts) {
				$value = shift(@parts);
				$infohash{$value} = shift(@parts);
			}
			foreach (sort { $a cmp $b } keys %infohash) {
				$return_text .= "$_: " . $infohash{$_} . "\n";
			}
		}
	}
	else {
		print "\nERROR:\n\t$ip_address:$port is not currently responding to requests.\n";
		print "\n\tSorry.  Try again later.\n\n";
	}
	return $return_text;
}

# END: get_server_info($ip_address)

# BEGIN: broadcast_message($message)
sub broadcast_message {
	my $message = shift;
	if ((!defined($message)) or ($message !~ /./)) { return; }
	my $num_servers = 0;
	my $config_val;
	my $rcon;
	$message = "say $name^1@^7$server_name^7: $message";

	foreach $config_val (@remote_servers) {
		if ($config_val =~ /^([\d\.]+):(\d+):(.*)$/) {
			my ($ip_address, $port, $password) = ($1, $2, $3);
			$num_servers++;
			$rcon = new KKrcon(
				Host     => $ip_address,
				Port     => $port,
				Password => $password,
				Type     => 'old'
			);
			print $rcon->execute($message);
		}
		else { print "WARNING: Invalid remote_server syntax: $config_val\n"; }
	}
	if (&flood_protection('broadcast', 30, $slot)) { return 1; }
	if ($num_servers == 0) {
		&rcon_command("say Unfortunately, no remote servers has been found. Check your config file.");
	}
	elsif ($num_servers == 1) {
		&rcon_command("say Your message has been successfully sent to your remote server.");
	}
	else {
		&rcon_command("say Your message has been successfully sent to ^1$num_servers ^7remote servers");
	}
}

# END: broadcast_message($message)

# BEGIN: nuke
sub nuke {
	if (&flood_protection('nuke', 30, $slot)) { return 1; }
	&rcon_command("say OH NO, he pushed the ^1BIG RED BUTTON^7!!!!!!!");
	sleep 1;
	&rcon_command("kick all");
	&log_to_file('logs/kick.log', "NUKE: ALL players were kicked by $name - GUID $guid - via !nuke command");
}

# END: nuke

# BEGIN: vote($vote_initiator,$vote_type,$vote_target)
sub vote {
	$vote_initiator = shift;
	$vote_type      = shift;
	$vote_target    = shift;
	if ($vote_started) { return 1; }
	elsif ($vote_type eq 'kick' or $vote_type eq 'ban') {
		my @matches = &matching_users($vote_target);
		if ($#matches == 0) {
			$vote_target      = $name_by_slot{$matches[0]};
			$vote_target_slot = $matches[0];
			if   ($vote_type eq 'kick') { &vote_start("Kick"); }
			else                        { &vote_start("Temporary ban"); }
		}
		elsif ($#matches > 0) {
			&rcon_command("say Too many matches for: $vote_target");
			return 1;
		}
		elsif ($#matches == -1) {
			&rcon_command("say No matches for: $vote_target");
			return 1;
		}
	}
	elsif ($vote_type eq 'map') {
		if ($vote_target =~ /^beltot\b|!farmhouse\b/i) {
			$vote_target = 'mp_farmhouse';
		}
		elsif ($vote_target =~ /^villers\b|^!breakout\b|^!vb\b|^!bocage\b|^!villers-bocage\b/i) {
			$vote_target = 'mp_breakout';
		}
		elsif ($vote_target =~ /^brecourt\b/i) {
			$vote_target = 'mp_brecourt';
		}
		elsif ($vote_target =~ /^b[ieu]rg[aeiou]?ndy\b/i) {
			$vote_target = 'mp_burgundy';
		}
		elsif ($vote_target =~ /^car[ie]nt[ao]n\b/i) {
			$vote_target = 'mp_carentan';
		}
		elsif ($vote_target =~ /^(st\.?mere|dawnville|egli[sc]e|st\.?mere.?egli[sc]e)\b/i) {
			$vote_target = 'mp_dawnville';
		}
		elsif ($vote_target =~ /^(el.?alamein|egypt|decoy)\b/i) {
			$vote_target = 'mp_decoy';
		}
		elsif ($vote_target =~ /^(moscow|downtown)\b/i) {
			$vote_target = 'mp_downtown';
		}
		elsif ($vote_target =~ /^len+[aeio]ngrad\b/i) {
			$vote_target = 'mp_leningrad';
		}
		elsif ($vote_target =~ /^matmata\b/i) {
			$vote_target = 'mp_matmata';
		}
		elsif ($vote_target =~ /^(st[ao]l[ie]ngrad|railyard)\b/i) {
			$vote_target = 'mp_railyard';
		}
		elsif ($vote_target =~ /^toujane\b/i) {
			$vote_target = 'mp_toujane';
		}
		elsif ($vote_target =~ /^(caen|train.?station)\b/i) {
			$vote_target = 'mp_trainstation';
		}
		elsif ($vote_target =~ /^(harbor|rostov)\b/i) {
			$vote_target = 'mp_harbor';
		}
		elsif ($vote_target =~ /^(rhine|wallendar)\b/i) {
			$vote_target = 'mp_rhine';
		}
		if (    ($cod_version eq '1.0')
			and ($vote_target =~ /mp_(harbor|rhine)/))
		{
			return 1;
		}
		&vote_start("Change map to^2");
	}
	elsif ($vote_type eq 'type') {
		if    ($vote_target =~ /^dm\b/i)  { $vote_target = 'dm'; }
		elsif ($vote_target =~ /^tdm\b/i) { $vote_target = 'tdm'; }
		elsif ($vote_target =~ /^hq\b/i)  { $vote_target = 'hq'; }
		elsif ($vote_target =~ /^ctf\b/i) { $vote_target = 'ctf'; }
		elsif ($vote_target =~ /^sd\b/i)  { $vote_target = 'sd'; }
		else                              { $vote_target = 'unknown'; }

		if ($vote_target =~ /^(dm|tdm|hq|ctf|sd)$/) {
			&vote_start("Change gametype to^3");
		}
	}
}

# END: vote

# BEGIN: vote_start($vote_string)
sub vote_start {
	if (&flood_protection('vote', 300)) { return 1; }
	$vote_string = shift;
	my $type = uc $vote_type;
	&rcon_command("say $vote_initiator ^7has started a vote: $vote_string " . &description($vote_target));
	sleep 1;
	$voting_players = $players_count;

	if (!$voting_players) {
		&rcon_command("say Not enough players to start a vote, try again later");
		return 1;
	}
	$vote_time = ($time + $vote_timelimit) + ($players_count * 5);    # +5 seconds for each player
	$required_yes = ($voting_players / 2) + 1;
	if ($required_yes =~ /^(\d+)(\.\d+)$/) { $required_yes = $1; }
	&rcon_command("say Vote started: Timelimit: ^4" . ($vote_time - $time) . " ^7seconds: ^2YES^7 needed: ^2$required_yes");
	sleep 1;
	&rcon_command("say Use ^5!yes ^7to vote ^2YES ^7or ^5!no ^7to vote ^1NO");
	sleep 1;
	&rcon_command("say Use ^5!votestatus ^7to check vote status");
	$vote_started = 1;
	&log_to_file('logs/voting.log', "!VOTE$type: $vote_initiator has started a vote: $vote_string $vote_target");
}

# END: vote_start

# BEGIN: vote_cleanup
sub vote_cleanup {
	$vote_started     = 0;
	$voted_yes        = 0;
	$voted_no         = 0;
	$voting_players   = 0;
	$required_yes     = 0;
	$vote_time        = 0;
	$vote_type        = undef;
	$vote_string      = undef;
	$vote_initiator   = undef;
	$vote_target      = undef;
	$vote_target_slot = undef;
	foreach $reset_slot (keys %voted_by_slot) {
		$voted_by_slot{$reset_slot} = 0;
	}
}

# END: vote_cleanup
