#!/usr/bin/perl

# VERSION 3.xx RUS changelog is on github page https://github.com/voron00/Nanny/commits/master

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
#  ability to specify tempban time via config? ...done

#  Command wish list:
#  !teambalance on/off ...done
#  !forcerespawn on/off ...done
#  !spectatefree on/off ...done
#  !rifles on/off/only
#  !bolt on/off/only
#  !mgs on/off/only

# NOTE:  rcon names have full color codes, kill lines have full colors, chat lines do not.

# List of modules
use warnings; # helps catch failure strings
use strict;   # strict keeps us from making stupid typos
use diagnostics; # good for detailed explanations about any problems in code
use Rcon::KKrcon;   # The KKrcon module used to issue commands to the server
use DBI; # databases
use Geo::IP; # GeoIP is used for locating IP addresses
use Geo::Inverse; # Used for calculating the distance from the server
use Time::Duration; # expresses times in plain english
use Time::Format; # easy to use time formatting
use Time::HiRes qw (usleep); # high resolution timers
use Socket; # Used for asking activision for GUID numbers for sanity check
use IO::Select; # also used by the udp routines for manual GUID lookup
use LWP::Simple; # HTTP fetches are used for the dictionary
use Net::FTP; # FTP support for remote logfiles
use File::Basename; # ftptail support
use File::Temp qw/ :POSIX /; # ftptail support
use Carp; # ftptail support

# Connect to sqlite databases
my $guid_to_name_dbh = DBI->connect("dbi:SQLite:dbname=databases/guid_to_name.db","","");
my $ip_to_guid_dbh = DBI->connect("dbi:SQLite:dbname=databases/ip_to_guid.db","","");
my $ip_to_name_dbh = DBI->connect("dbi:SQLite:dbname=databases/ip_to_name.db","","");
my $seen_dbh = DBI->connect("dbi:SQLite:dbname=databases/seen.db","","");
my $stats_dbh = DBI->connect("dbi:SQLite:dbname=databases/stats.db","","");
my $bans_dbh = DBI->connect("dbi:SQLite:dbname=databases/bans.db","","");
my $definitions_dbh = DBI->connect("dbi:SQLite:dbname=databases/definitions.db","","");
my $names_dbh = DBI->connect("dbi:SQLite:dbname=databases/names.db","","");
my $ranks_dbh = DBI->connect("dbi:SQLite:dbname=databases/ranks.db","","");

# Global variable declarations
my $version = '3.3 RUS svn 19';
my $idlecheck_interval = 45;
my %idle_warn_level;
my $namecheck_interval = 40;
my %name_warn_level;
my $last_namecheck;
my $tempbantime = 30;
my $rconstatus_interval = 30;
my $guid_sanity_check_interval = 597;
my $problematic_characters = "\[^\x00-\x7F]+";
my $config;
my $line;
my $first_char;
my $slot;
my $guid;
my $name;
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
my %last_activity_by_slot;
my $last_idlecheck;
my $last_rconstatus;
my %name_by_slot;
my %fake_name_by_slot;
my %ip_by_slot;
my %guid_by_slot;
my %ping_by_slot;
my %spam_last_said;
my %spam_count;
my $sth;
my $bans_sth;
my $seen_sth;
my $stats_sth;
my $names_sth;
my $ranks_sth;
my %last_ping;
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
my $most_recent_guid = 0;
my $most_recent_slot = 0;
my $most_recent_time = 0;
my $last_guid_sanity_check;
my $uptime = 0;
my %flood_protect;
my $first_blood = 1;
my %last_killed_by;
my %kill_spree;
my %best_spree;
my $next_announcement;
my $voting = 1;
my $reactivate_voting = 0;
my %location_spoof;
my $game_type;
my $game_name;
my $map_name;
my $friendly_fire = 0;
my $kill_cam = 1;
my $cod_version;
my $server_name;
my $max_clients = 999;
my $max_ping = 999;
my $private_clients = 0;
my $pure = 1;
my $chatmode;
my $voice = 0;
my $last_guid0_audit = time;
my $guid0_audit_interval = 295;
my %ignore;
my $ftp_lines = 0;
my $ftp_inbandSignaling = 0;
my $ftp_verbose = 1;
my $ftp_host = '';
my $ftp_dirname = '';
my $ftp_basename = '';
my $ftp_tmpFileName = '';
my $ftp_currentEnd;
my $ftp_lastEnd;
my $ftp_type; 
my $logfile_mode = 'local'; # local cod server logfile is the default vs. remote ftp logfile
my @ftp_buffer;
my $ftp;
my $next_map;
my $next_gametype;
my $freshen_next_map_prediction = 1;
my $temporary;
my %description;
my $now_upmins = 0;
my $last_upmins = 0;
my @affiliate_servers;
my @affiliate_server_prenouncements;
my $next_affiliate_announcement;
my %servername_cache;
my @remote_servers;
my $ftpfail = 0;

# turn on auto-flush for STDOUT
$| = 1;

# shake the snow-globe.
srand;

# Read the configuration from the .cfg file.
&load_config_file('nanny.cfg');

# Open the server logfile for reading.
if ($logfile_mode eq 'local') {
    &open_server_logfile($config->{'server_logfile_name'});
    # Seek to the end of the logfile
    seek(LOGFILE, 0, 2);
}
elsif ($logfile_mode eq 'ftp') { &ftp_connect }

# Initialize the database tables if they do not exist
&initialize_databases;

# Startup message
print "================================================================================\n";

print "                     Сиделка для сервера Call of Duty 2\n";
print "                          Версия $version\n";
print "                            Автор - smugllama\n";
print "                       Доработка и перевод - VoroN\n\n";

print "                       RCON-модуль основан на KKrcon\n";
print "                       http://kkrcon.sourceforge.net\n\n";

print "                    IP-Геолокация предоставлена MaxMind\n";
print "                         http://www.maxmind.com\n\n";

print "                    Поддержка удаленных FTP лог-файлов\n";
print "                    основана на ftptail от Will Moffat\n";
print "                  http://hamstersoup.wordpress.com/ftptail\n\n";

print "                 Оригинанльная версия NannyBot доступна на:\n";
print "                      http://smaert.com/nannybot.zip\n\n";

print "                   Последняя Русская версия доступна на:\n";
print "                     https://github.com/voron00/Nanny\n\n";

print "================================================================================\n";

# initialize the timers
$time = time;
$last_idlecheck = $time;
$last_rconstatus = 0;
$last_namecheck = $time;
$last_guid_sanity_check = $time;
$timestring = scalar(localtime($time));
$next_announcement = $time + 120;
$next_affiliate_announcement = $time;

# create the rcon control object - this is how we send commands to the console
my $rcon = new KKrcon (Host => $config->{'ip'}, Port => $config->{'port'}, Password => $config->{'rcon_pass'}, Type => 'old');

# tell the server that we want the game logfiles flushed to disk after every line.
&rcon_command("g_logSync 1");

# Ask which version of CoD2 server is currently running
$temporary = &rcon_query('shortversion');
if ($temporary =~ /\"shortversion\" is: \"(\d+\.\d+)\^7\"/m) {
   $cod_version = $1;
   if ($cod_version =~ /./) { print "CoD2 version is: $cod_version\n"; }
 }
else { print "WARNING: unable to parse cod_version:  $temporary\n"; }

# Ask the server what it's official name is
$temporary = &rcon_query("sv_hostname");
if ($temporary =~ /\"sv_hostname\" is: \"([^\"]+)\"/m) {
    $server_name = $1;
    $server_name =~ s/\^7$//;
    if ($server_name =~ /./) { print "Server Name is: $server_name\n"; }
}
else { print "WARNING: cant parse the sv_hostname results.\n"; }

# Ask the server if voting is currently turned on or off
$temporary = &rcon_query("g_allowVote");
if ($temporary =~ /\"g_allowVote\" is: \"(\d+)\^7\"/m) {
    $voting = $1;
    if ($voting) { print "Voting is currently turned ON\n"; }
    else { print "Voting is currently turned OFF\n"; }
}
else { print "Sorry, cant parse the g_allowVote results.\n"; }

# Ask which map is now present
$temporary = &rcon_query('mapname');
if ($temporary =~ /\"mapname\" is: \"(\w+)\^7\"/m) {
   $map_name = $1;
   if ($map_name =~ /./) { print "Current map is: $map_name\n"; }
   }
else { print "WARNING: unable to parse game_type:  $temporary\n"; }

# Ask which gametype is now present
$temporary = &rcon_query('g_gametype');
if ($temporary =~ /\"g_gametype\" is: \"(\w+)\^7\"/m) {
   $game_type = $1;
   if ($game_type =~ /./) { print "Gametype is: $game_type\n"; }
   }
else { print "WARNING: unable to parse game_type:  $temporary\n"; }

# Main Loop
while (1) {

    if ($logfile_mode eq 'local') { $line = <LOGFILE>; }
	elsif ($logfile_mode eq 'ftp') { $line = &ftp_get_line; }

    if (defined($line)) {
	# We have a new line from the logfile.

	# make sure our line is complete.
	if ($line !~ /\n/) {
	    # incomplete, save this for next time.
	    $partial = $line;
	    next;
	}

	# if we have any previous leftovers, prepend them.
	if ($partial ne '') {
	    $line = $partial . $line;
	    $partial = '';
	}

	# Strip the timestamp from the begining
	if ($line =~ /^\s{0,2}(\d+:\d+)\s+(.*)/) {
	    ($uptime,$line) = ($1,$2);

	    # BEGIN: SERVER CRASH / RESTART detection
	    # detect when the uptime gets smaller.
	    if ($uptime =~ /^(\d+):/) {
		$now_upmins = $1;
		if ($now_upmins < $last_upmins) {
		    # we can infer that the server crashed or was restarted when the uptime shrinks.
		    # use this to trigger an auto-reset.
		    my $reset_slot;
		    foreach $reset_slot (keys %last_activity_by_slot) {
		    $last_activity_by_slot{$reset_slot} = 'gone';
		    $idle_warn_level{$reset_slot} = 0;
		    &update_name_by_slot('SLOT_EMPTY', $reset_slot);
		    $ip_by_slot{$reset_slot} = 'not_yet_known';
		    $guid_by_slot{$reset_slot} = 0;
		    $spam_count{$reset_slot} = 0;
			$spam_last_said{$slot} = &random_pwd(6);
			$ping_by_slot{$slot} = 0;
		    $last_ping{$reset_slot} = 0;
		    $penalty_points{$reset_slot} = 0;
		    $last_killed_by{$reset_slot} = 'none';
		    $kill_spree{$reset_slot} = 0;
		    $best_spree{$reset_slot} = 0;
		    $ignore{$reset_slot} = 0;
			$fake_name_by_slot{$reset_slot} = undef;
			}
	        print "SERVER CRASH/RESTART DETECTED, RESETTING...\n";
		    &rcon_command("say " , '"^1*** ^7Похоже что сервер упал, перезапускаю себя... ^1***"');
		}
		$last_upmins = $now_upmins;
	    }
	    # END: SERVER CRASH / RESTART detection
	}

	# Strip the newline and any trailing space from the end.
	$line =~ s/\s+$//;

	# hold onto the first character of the line
	# doing single character eq is faster than regex ~=
	$first_char = substr($line, 0, 1);

	# Which class of event is the line we just read?
	if ($first_char eq 'K') {
	    # A "KILL" Event has happened
	    if ($line =~ /^K;(\d+);(\d+);(allies|axis|);([^;]+);(\d*);([\d\-]+);(allies|axis|world|spectator|);([^;]*);(\w+);(\d+);(\w+);(\w+)/) {
		($victim_guid, $victim_slot, $victim_team, $victim_name, $attacker_guid, $attacker_slot, $attacker_team,
		$attacker_name, $attacker_weapon, $damage, $damage_type, $damage_location) = ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12);
        $attacker_name =~ s/$problematic_characters//g;
        $victim_name =~ s/$problematic_characters//g;

		# the RIDDLER fix, try #1
		$attacker_name =~ s/\s+$//;
		$victim_name =~ s/\s+$//;

		if (($attacker_guid) && ($attacker_name)) { &cache_guid_to_name($attacker_guid, $attacker_name); }
		if (($victim_guid) && ($victim_name)) { &cache_guid_to_name($victim_guid, $victim_name); }
		$last_activity_by_slot{$attacker_slot} = $time;

		&update_name_by_slot($attacker_name, $attacker_slot);
		&update_name_by_slot($victim_name, $victim_slot);

		$guid_by_slot{$attacker_slot} = $attacker_guid;
		$guid_by_slot{$victim_slot} = $victim_guid;
		$last_killed_by{$victim_slot} = $attacker_name;

		# Glitch Server Mode
		if ($config->{'glitch_server_mode'}) {
			print "GLITCH SERVER MODE:  " . &strip_color($attacker_name) . " killed someone.  Kicking!\n";
			&rcon_command("say ^1" . $attacker_name . ":^1 " . $config->{'glitch_kill_kick_message'});
			print &strip_color($attacker_name) . ": " . $config->{'glitch_kill_kick_message'} . "\n"; 
			sleep 1;
			&rcon_command("clientkick $attacker_slot");
			&log_to_file('logs/kick.log', "GLITCH_KILL: Murderer!  Kicking $attacker_name for killing other people");
		}
		# Track the kill stats for the killer
		if ($attacker_slot ne $victim_slot) {
		    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE name=?");
		    $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		    @row = $stats_sth->fetchrow_array;
		    if ($row[0]) {
			if ($damage_location eq 'head') {
			    $stats_sth = $stats_dbh->prepare("UPDATE stats SET kills=?,headshots=? WHERE name=?");
			    $stats_sth->execute(($row[2] + 1), ($row[4] + 1), &strip_color($attacker_name)) or &die_nice("Unable to do update\n");
			}
			else {
			    $stats_sth = $stats_dbh->prepare("UPDATE stats SET kills=? WHERE name=?");
			    $stats_sth->execute(($row[2] + 1), &strip_color($attacker_name)) or &die_nice("Unable to do update\n");
			}
		    }
		    else {
			$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)");
			if ($damage_location eq 'head') {
			    $stats_sth->execute(&strip_color($attacker_name), 1, 0, 1) or &die_nice("Unable to do insert\n");
			}
			else {
			    $stats_sth->execute(&strip_color($attacker_name), 1, 0, 0) or &die_nice("Unable to do insert\n");
			}
		    }
		    # Grenade Kills
		    if ($damage_type eq 'MOD_GRENADE_SPLASH') {
			    $stats_sth = $stats_dbh->prepare("UPDATE stats SET grenade_kills = grenade_kills + 1 WHERE name=?");
                $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
		    }
		    # Pistol Kills
		    if ($attacker_weapon =~ /^(webley|colt|luger|TT30)_mp$/) {
			    $stats_sth = $stats_dbh->prepare("UPDATE stats SET pistol_kills = pistol_kills + 1 WHERE name=?");
                $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
		    }
		    # Bash / Melee Kills
            if ($damage_type eq 'MOD_MELEE') {
                $stats_sth = $stats_dbh->prepare("UPDATE stats SET bash_kills = bash_kills + 1 WHERE name=?");
                $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
            }
            # Shotgun Kills
            if ($attacker_weapon eq 'shotgun_mp') {
                $stats_sth = $stats_dbh->prepare("UPDATE stats SET shotgun_kills = shotgun_kills + 1 WHERE name=?");
                $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
            }
            # Sniper Kills
            if ($attacker_weapon =~ /^(enfield_scope|springfield|mosin_nagant_sniper|kar98k_sniper)_mp$/) {
                $stats_sth = $stats_dbh->prepare("UPDATE stats SET sniper_kills = sniper_kills + 1 WHERE name=?");
                $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
            }
            # Rifle Kills
            if ($attacker_weapon =~ /^(enfield|m1garand|m1carbine|mosin_nagant|SVT40|kar98k|g43)_mp$/) {
                $stats_sth = $stats_dbh->prepare("UPDATE stats SET rifle_kills = rifle_kills + 1 WHERE name=?");
                $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
            }
		    # Machinegun Kills
            if ($attacker_weapon =~ /^(sten|thompson|bren|greasegun|bar|PPS42|ppsh|mp40|mp44|30cal_stand|mg42_bipod_stand)_mp$/) {
                $stats_sth = $stats_dbh->prepare("UPDATE stats SET machinegun_kills = machinegun_kills + 1 WHERE name=?");
                $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
            }
		}
		# Track the death stats for the victim
		if ($victim_slot ne $attacker_slot) {
		    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE name=?");
		    $stats_sth->execute(&strip_color($victim_name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		    @row = $stats_sth->fetchrow_array;
		    if ($row[0]) {
			$stats_sth = $stats_dbh->prepare("UPDATE stats SET deaths=? WHERE name=?");
			$stats_sth->execute(($row[3] + 1), &strip_color($victim_name)) or &die_nice("Unable to do update\n");
		    }
		    else {
			$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)");
			$stats_sth->execute(&strip_color($victim_name), 0, 1, 0) or &die_nice("Unable to do insert\n");
		    }
		}
		# End of kill-stats tracking

		# print the kill to the screen
		if ($damage_location eq 'head') {
		if ($config->{'show_headshots'}) { print "HEADSHOT: " . &strip_color($attacker_name) . " killed " . &strip_color($victim_name) . " - HEADSHOT!\n"; }
		&log_to_file('logs/kills.log', "HEADSHOT: " . &strip_color($attacker_name) . " killed " . &strip_color($victim_name) . " - HEADSHOT!");
		}
		else {
		    if ($config->{'show_kills'}) {
			if ($victim_slot eq $attacker_slot) { print "SUICIDE: " . &strip_color($attacker_name) . " killed himself\n"; }
			elsif ($damage_type eq 'MOD_FALLING') { print "FALL: " . &strip_color($victim_name) . " fell to their death\n"; }
			else { print "KILL: " . &strip_color($attacker_name) . " killed " . &strip_color($victim_name) . "\n"; }
		    }
			if ($victim_slot eq $attacker_slot) { &log_to_file('logs/kills.log', "SUICIDE: " . &strip_color($attacker_name) . " killed himself"); }
			elsif ($damage_type eq 'MOD_FALLING') { &log_to_file('logs/kills.log', "FALL: " . &strip_color($victim_name) . " fell to their death"); }
			else { &log_to_file('logs/kills.log', "KILL: " . &strip_color($attacker_name) . " killed " . &strip_color($victim_name)); }
		}
		# First Blood
		if (($config->{'first_blood'}) && ($first_blood == 0) && ($attacker_slot ne $victim_slot) && ($attacker_slot >= 0)) {
		    $first_blood = 1;
		    &rcon_command("say " . '"ПЕРВАЯ КРОВЬ:^1"' . &strip_color($attacker_name) . '"^7убил^2"' . &strip_color($victim_name));
		    print "FIRST BLOOD: " . &strip_color($attacker_name) . " killed " . &strip_color($victim_name) . "\n";
			# First blood stats tracking
			$stats_sth = $stats_dbh->prepare("UPDATE stats SET first_bloods = first_bloods + 1 WHERE name=?");
		    $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats\n");
		}
		# Killing Spree
		if (($config->{'killing_sprees'}) && ($damage_type ne 'MOD_SUICIDE') && ($damage_type ne 'MOD_FALLING') && ($attacker_team ne 'world') && ($attacker_slot ne $victim_slot)) {
		    if (!defined($kill_spree{$attacker_slot})) { $kill_spree{$attacker_slot} = 1; }
			else { $kill_spree{$attacker_slot} += 1; } 
		    if (defined($kill_spree{$victim_slot})) {
			if (!defined($best_spree{$victim_slot})) { $best_spree{$victim_slot} = 0; }
			if (($kill_spree{$victim_slot} > 2) && ($kill_spree{$victim_slot} > $best_spree{$victim_slot})) {
			    $best_spree{$victim_slot} = $kill_spree{$victim_slot};  
			    $stats_sth = $stats_dbh->prepare("SELECT best_killspree FROM stats WHERE name=?");
			    $stats_sth->execute(&strip_color($victim_name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
			    @row = $stats_sth->fetchrow_array;
			    if ((defined($row[0])) && ($row[0] < $best_spree{$victim_slot})) {
				$stats_sth = $stats_dbh->prepare("UPDATE stats SET best_killspree=? WHERE name=?");
				$stats_sth->execute($best_spree{$victim_slot}, &strip_color($victim_name)) or &die_nice("Unable to update stats\n");
				&rcon_command("say ^1" . &strip_color($attacker_name) . '"^7остановил ^2*^1РЕКОРДНУЮ^2* ^7серию убийств для игрока^2"' . &strip_color($victim_name) . '"^7который убил"' . "^6$kill_spree{$victim_slot}^7" . '"человек"');
				}
                else { &rcon_command("say ^1" . &strip_color($attacker_name) . '"^7остановил серию убийств игрока^2"' . &strip_color($victim_name) . '"^7который убил"' . "^6$kill_spree{$victim_slot}^7" . '"человек"'); }
			}
		    }
		    $kill_spree{$victim_slot} = 0;
			$best_spree{$victim_slot} = 0;
		}
		# End of Kill-Spree section
	    }
		else { print "WARNING: unrecognized syntax for kill line:\n\t$line\n"; }
	}
	elsif ($first_char eq 'D') {
	    # A "DAMAGE" event has happened.
	    if ($line =~ /^D;(\d+);(\d+);(allies|axis|);([^;]+);(\d*);([\d\-]+);(allies|axis|world|spectator|);([^;]*);(\w+);(\d+);(\w+);(\w+)/) {
		($victim_guid, $victim_slot, $victim_team, $victim_name, $attacker_guid, $attacker_slot, $attacker_team,
		$attacker_name, $attacker_weapon, $damage, $damage_type, $damage_location) = ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12);
		$attacker_name =~ s/$problematic_characters//g;
        $victim_name =~ s/$problematic_characters//g;
        if (($attacker_guid) && ($attacker_name)) { &cache_guid_to_name($attacker_guid, $attacker_name); }
		if (($victim_guid) && ($victim_name)) { &cache_guid_to_name($victim_guid, $victim_name); }
		$last_activity_by_slot{$attacker_slot} = $time;
        &update_name_by_slot($attacker_name, $attacker_slot);
        &update_name_by_slot($victim_name, $victim_slot);
		$guid_by_slot{$attacker_slot} = $attacker_guid;
		$guid_by_slot{$victim_slot} = $victim_guid;
		}
	    else { print "WARNING: unrecognized syntax for damage line:\n\t$line\n"; }
	}
	elsif ($first_char eq 'J') {
	    # A "JOIN" Event has happened
	    # WARNING:  This join does not only mean they just connected to the server
	    # it can also mean that the level has changed.
	    if ($line =~ /^J;(\d+);(\d+);(.*)/) {
		($guid,$slot,$name) = ($1,$2,$3);
		$name =~ s/$problematic_characters//g;
		# cache the guid and name
		if (($guid) && ($name)) {
		    &cache_guid_to_name($guid,$name);
		    $most_recent_guid = $guid;
		    $most_recent_slot = $slot;
		    $most_recent_time = $time;
		}
		$last_activity_by_slot{$slot} = $time;
		$idle_warn_level{$slot} = 0;
		$guid_by_slot{$slot} = $guid;
		&update_name_by_slot($name, $slot);
		$ip_by_slot{$slot} = 'not_yet_known';
		$spam_count{$slot} = 0;
		$spam_last_said{$slot} = &random_pwd(6);
		$ping_by_slot{$slot} = 0;
		$last_ping{$slot} = 0;
		$kill_spree{$slot} = 0;
		$best_spree{$slot} = 0;
		$last_killed_by{$slot} = 'none';
		$penalty_points{$slot} = 0;
		$ignore{$slot} = 0;
		# assign fake name to a player
		$names_sth = $names_dbh->prepare("SELECT * FROM names ORDER BY RANDOM() LIMIT 1;");
        $names_sth->execute() or &die_nice("Unable to execute query: $names_dbh->errstr\n");
		@row = $names_sth->fetchrow_array;
	    if (!$row[0]) { $fake_name_by_slot{$slot} = '^2В базе данных нет имен, используйте !addname чтобы добавить имена'; }
		else { $fake_name_by_slot{$slot} = $row[1]; }
		# end of fake name assigning
		if (($config->{'show_game_joins'}) && ($game_type ne 'sd')) { &rcon_command("say " . '"'. "$name" . '^7 присоединился к игре'); }
		if ($config->{'show_joins'}) { print "JOIN: " . &strip_color($name) . " has joined the game\n"; }
		# Check for banned GUID
		&check_banned_guid($guid,$name,$slot);
        }
	    else { print "WARNING: unrecognized syntax for join line:\n\t$line\n"; }
	}
	elsif ($first_char eq 'Q') {
	    # A "QUIT" Event has happened
	    if ($line =~ /^Q;(\d+);(\d+);(.*)/) {
		($guid,$slot,$name) = ($1,$2,$3);
		$name =~ s/$problematic_characters//g;
		# cache the guid and name
		if (($guid) && ($name)) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = 'gone';
		$idle_warn_level{$slot} = 0;
		&update_name_by_slot('SLOT_EMPTY', $slot);
		$ip_by_slot{$slot} = 'SLOT_EMPTY';
		$guid_by_slot{$slot} = 0;
		$spam_count{$slot} = 0;
		$ping_by_slot{$slot} = 0;
        $last_ping{$slot} = 0;
		$penalty_points{$slot} = 0;
		$last_killed_by{$slot} = 'none';
		$kill_spree{$slot} = 0;
		$best_spree{$slot} = 0;
		$ignore{$slot} = 0;
		$fake_name_by_slot{$slot} = undef;
		# populate the seen data
		$seen_sth = $seen_dbh->prepare("UPDATE seen SET time=? WHERE name=?");
		$seen_sth->execute($time,$name) or &die_nice("Unable to do update\n");
		# end of seen data population
        if ($config->{'show_quits'}) { print "QUIT: " . &strip_color($name) . " has left the game\n"; }
		if ($config->{'show_game_quits'}) { &rcon_command("say " . '"'. "$name" . '^7 покинул игру'); }
        }
	    else { print "WARNING: unrecognized syntax for quit line:\n\t$line\n"; }
	}
	elsif ($first_char eq 's') {
	    # say / sayteam
	    if ($line =~ /^say;(\d+);(\d+);([^;]+);(.*)/) {
		# a "SAY" event has happened
		($guid,$slot,$name,$message) = ($1,$2,$3,$4);
		if (($guid) && ($name)) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = $time;
		&update_name_by_slot($name, $slot);
		$guid_by_slot{$slot} = $guid;
		$message =~ s/^\x15//;
		&chat($chatmode = 'global');
	    }
		elsif ($line =~ /^sayteam;(\d+);(\d+);([^;]+);(.*)/) {
		# a "SAYTEAM" event has happened
		($guid,$slot,$name,$message) = ($1,$2,$3,$4);
		if (($guid) && ($name)) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = $time;
		&update_name_by_slot($name, $slot);
		$guid_by_slot{$slot} = $guid;
		$message =~ s/^\x15//;
		&chat($chatmode = 'team');
        }
	    # else { print "WARNING: unrecognized syntax for say line:\n\t$line\n"; }   
	}
	elsif ($first_char eq 't') {
            # say / sayteam
            if ($line =~ /^tell;(\d+);(\d+);([^;]+);\d+;\d+;[^;]+;(.*)/) {
                # a "tell" (private message) event has happened
                ($guid,$slot,$name,$message) = ($1,$2,$3,$4);
                if (($guid) && ($name)) { &cache_guid_to_name($guid,$name); }
                $last_activity_by_slot{$slot} = $time;
                &update_name_by_slot($name, $slot);
                $guid_by_slot{$slot} = $guid;
                $message =~ s/^\x15//;
                &chat($chatmode = 'private');
            }
            # else { print "WARNING: unrecognized syntax for tell line:\n\t$line\n"; }
        }
	elsif ($first_char eq 'W') {
	    if ($line =~ /^Weapon;(\d+);(\d+);([^;]*);(\w+)$/) {
		# a "WEAPON" Event has happened
		($guid,$slot,$name,$weapon) = ($1,$2,$3,$4);
		$name =~ s/$problematic_characters//g;
		# cache the guid and name
		if (($guid) && ($name)) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = $time;
		&update_name_by_slot($name, $slot);
		$guid_by_slot{$slot} = $guid;
	    }
		elsif ($line =~ /^W;([^;]*);(\d+);([^;]*)/) {
		# a "Round Win" Event has happened
		($attacker_team,$guid,$name) = ($1,$2,$3);
		$name =~ s/$problematic_characters//g;
		if ((defined($attacker_team)) && ($attacker_team =~ /./)) { print "GAME OVER: $attacker_team have WON this game of $game_type on $map_name\n"; }
		else { print "GAME OVER: $name has WON this game of $game_type on $map_name\n"; }
		# cache the guid and name
		if (($guid) && ($name)) { &cache_guid_to_name($guid,$name); }
	    }
		# else { print "WARNING: unrecognized syntax for Weapon/Round Win line:\n\t$line\n"; }
	}
	elsif ($first_char eq 'L') {
	    # Round Losers
	    if ($line =~ /^L;([^;]*);(\d+);([^;]*)/) {
		($attacker_team,$guid,$name) = ($1,$2,$3);
		if ((defined($attacker_team)) && ($attacker_team =~ /./)) { print "GAME OVER: $attacker_team have LOST this game of $game_type on $map_name\n"; }
		else { print "... apparently there are no losers\n"; }
		}
	    # else { print "WARNING: unrecognized syntax for Round Loss line:\n\t$line\n"; }
	}
	elsif ($first_char eq 'I') {
	    # Init Level
	    if ($line =~ /\\g_gametype\\([^\\]+)/) { $game_type = $1; }
	    if ($line =~ /\\gamename\\([^\\]+)/) { $game_name = $1; }
	    if ($line =~ /\\mapname\\([^\\]+)/) { $map_name = $1; }
	    if ($line =~ /\\scr_friendlyfire\\([^\\]+)/) { $friendly_fire = $1; }
        if ($line =~ /\\scr_killcam\\([^\\]+)/) { $kill_cam = $1; }
	    if ($line =~ /\\shortversion\\([^\\]+)/) { $cod_version = $1; }
	    if ($line =~ /\\sv_hostname\\([^\\]+)/) { $server_name = $1; }
        if ($line =~ /\\sv_maxclients\\([^\\]+)/) { $max_clients = $1; }
	    if ($line =~ /\\sv_maxPing\\([^\\]+)/) { $max_ping = $1; }
	    if ($line =~ /\\sv_privateClients\\([^\\]+)/) { $private_clients = $1; }
        if ($line =~ /\\sv_pure\\([^\\]+)/) { $pure = $1; }
        if ($line =~ /\\sv_voice\\([^\\]+)/) { $voice = $1; }
	    print "MAP STARTING: $map_name $game_type\n";
		# prepare for First Blood
		$first_blood = 0;
		# anti-vote-rush
		# first, look up the game-type so we can exempt S&D
		if (($voting) && ($config->{'anti_vote_rush'}) && ($game_type ne 'sd')) {
		    print "ANTI-VOTE-RUSH:  Turned off voting for 25 seconds...\n";
		    &rcon_command("g_allowVote 0");
		    $reactivate_voting = $time + 25;
		}
		# Buy some time so we don't do an rcon status during a level change
		if ($game_type ne 'sd') { $last_rconstatus = $time; }
		# Do rcon status if sd gametype
		if ($game_type eq 'sd') { $last_rconstatus = 0; }
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
	elsif ($first_char eq 'A') {
	    if ($line =~ /^A;(\d+);(\d+);(\w+);(.*);bomb_plant/) {
		($guid,$slot,$attacker_team,$name) = ($1,$2,$3,$4);
		$name =~ s/$problematic_characters//g;
		print "BOMB: " . &strip_color($name) . " planted the bomb\n";
		# bomb plants stats tracking
		$stats_sth = $stats_dbh->prepare("UPDATE stats SET bomb_plants = bomb_plants + 1 WHERE name=?");
		$stats_sth->execute(&strip_color($name)) or &die_nice("Unable to update stats\n");
	    }
		elsif ($line =~ /^A;(\d+);(\d+);(\w+);(.*);bomb_defuse/) {
        ($guid,$slot,$attacker_team,$name) = ($1,$2,$3,$4);
		$name =~ s/$problematic_characters//g;
        print "BOMB: " . &strip_color($name) . " defused the bomb\n";
		# bomb defuses stats tracking
		$stats_sth = $stats_dbh->prepare("UPDATE stats SET bomb_defuses = bomb_defuses + 1 WHERE name=?");
		$stats_sth->execute(&strip_color($name)) or &die_nice("Unable to update stats\n");
		}
        else { print "WARNING: unrecognized A line format:\n\t$line\n"; }
	}
	elsif (($first_char eq chr(13)) or ($first_char eq '')) {
	    # Empty Line
	}
	else {
	    # Unknown line
	    print "UNKNOWN LINE: $first_char and $line\n";
	}
    }
	else {
	# We have reached the end of the logfile.
	# Delay some time so we aren't constantly hammering this loop
	usleep(10000);
	# cache the time to limit the number of syscalls
	$time = time;
	$timestring = scalar(localtime($time));
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
    # Check if it is time to make our next announement yet.
    if (($time >= $next_announcement) && ($config->{'use_announcements'})) {
        $next_announcement = $time + (60*($config->{'interval_min'} + int(rand($config->{'interval_max'} - $config->{'interval_min'} + 1))));
        &make_announcement;
    }
	# Check if it is time to make our next affiliate server announement yet.
	if ($config->{'affiliate_server_announcements'}) {
	    if ($time >= $next_affiliate_announcement) {
		$next_affiliate_announcement = $time + $config->{'affiliate_server_announcement_interval'};
		&make_affiliate_server_announcement;
	    }
	}
	# Check to see if its time to reactivate voting
	if (($reactivate_voting) && ($time >= $reactivate_voting)) {
	    $reactivate_voting = 0;
	    if ($voting) {
		&rcon_command("g_allowVote 1");
		print "ANTI-VOTE-RUSH: Reactivated Voting...\n";
	    }
	}
	# Check to see if it's time to audit a GUID 0 person
	if (($config->{'audit_guid0_players'}) && (($time - $last_guid0_audit) >= ($guid0_audit_interval))) {
            $last_guid0_audit = $time;
            &check_guid_zero_players;
        }
	# Check to see if we need to predict the next level
	if ($freshen_next_map_prediction) {
	    $temporary = &rcon_query('sv_mapRotationCurrent');
	    if ($temporary =~ /\"sv_mapRotationCurrent\" is: \"\s*gametype\s+(\w+)\s+map\s+(\w+)/m) {
		($next_gametype,$next_map) = ($1,$2);
		if (!defined($description{$next_gametype})) { $description{$next_gametype} = $next_gametype }
		if (!defined($description{$next_gametype})) { $description{$next_map} = $next_map }
		print "Next Map:  " . $description{$next_map} .  " and Next Gametype: " .  $description{$next_gametype} . "\n"; 
		$freshen_next_map_prediction = 0;
	    }
		else {
		$temporary = &rcon_query('sv_mapRotation');
		if ($temporary =~ /\"sv_mapRotation\" is: \"\s*gametype\s+(\w+)\s+map\s+(\w+)/m) {
		    ($next_gametype,$next_map) = ($1,$2);
		    if (!defined($description{$next_gametype})) { $description{$next_gametype} = $next_gametype }
		    if (!defined($description{$next_gametype})) { $description{$next_map} = $next_map }
		    print "Next Map:  " . $description{$next_map} .  " and Next Gametype: " .  $description{$next_gametype} . "\n";
		    $freshen_next_map_prediction = 0;
		}
		# If maprotation contatins only space(empty) character, next map and gametype will be current map and gametype
		elsif ($temporary =~ /\"sv_mapRotation\" is: \"\s+/m) {
		    ($next_gametype,$next_map) = ($game_type,$map_name);
	        if (!defined($description{$next_gametype})) { $description{$next_gametype} = $next_gametype }
		    if (!defined($description{$next_gametype})) { $description{$next_map} = $next_map }
		    print "Next Map:  " . $description{$next_map} .  " and Next Gametype: " .  $description{$next_gametype} . "\n";
		    $freshen_next_map_prediction = 0;
		}
		else {
		print "WARNING: unable to predict next map:  $temporary\n";
		$freshen_next_map_prediction = 0;
		}
	    }
	}
    }
}
# End of main program

# Begin - subroutines

# BEGIN: load_config_file(file)
# Load the .cfg file
#  This routine parses the configuration file for directives.
sub load_config_file {
    my $config_file = shift;
    if (!defined($config_file)) { &die_nice("load_config_file called without an argument\n"); }
    if (!-e $config_file) { &die_nice("config file does not exist: $config_file\n"); }

    open (CONFIG, $config_file) or &die_nice("$config_file file exists, but i couldnt open it.\n");

    my $line;
    my $config_name;
    my $config_val;
    my $command_name;
    my $temp;
    my $rule_name = 'undefined';
    my $response_count = 1;
    my $regex_match;
    my $location;

    print "\nParsing config file: $config_file\n\n";

    while (defined($line = <CONFIG>)) {
	$line =~ s/\s+$//;
	if ($line =~ /^\s*(\w+)\s*=\s*(.*)/) {
	    ($config_name,$config_val) = ($1,$2);
	    if ($config_name eq 'ip_address') {
		$config->{'ip'} = $config_val;
		if ($config_val eq 'localhost|loopback') { $config->{'ip'} = '127.0.0.1'; }
		print "Server IP address: $config->{'ip'}\n"; 
	    }
	    elsif ($config_name eq 'port') { 
		$config->{'port'} = $config_val;
		print "Server port number: $config->{'port'}\n";
	    } 
	    elsif ($config_name eq 'rule_name') {
		$rule_name = $config_val;
		$response_count = 1;
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
                    print "\tUse the format:  description = term = Description\n";
                }
            }
	    elsif ($config_name eq 'match_text') { $rule_regex{$rule_name} = $config_val; }
	    elsif ($config_name eq 'penalty') { $rule_penalty{$rule_name} = $config_val; }
	    elsif ($config_name eq 'response') {
		$number_of_responses{$rule_name} = $response_count;
		$rule_response->{$rule_name}->{$response_count++} = $config_val;
	    }
	    elsif ($config_name =~ /^auth_(\w+)/) {
		$command_name = $1;
		if (!defined($config->{'auth'}->{$command_name})) {
		    $config->{'auth'}->{$command_name} = $config_val;
		    if ($config_val =~ /disabled/i) { print "!$command_name command is DISABLED\n"; }
		    else { print "Allowing $config_val to use the $command_name command\n"; }
		}
		else {
		    $temp = $config->{'auth'}->{$command_name};
		    $temp .= ',' . $config_val;
		    $config->{'auth'}->{$command_name} = $temp;
		    if ($config_val =~ /disabled/i) { print "\nWARNING:  $command_name is disabled and enabled.  Which is it?\n\n"; }
		    else { print "Also allowing $config_val to use the $command_name command\n"; }
		}
	    }
	    elsif ($config_name eq 'rcon_pass') {
		$config->{'rcon_pass'} = $config_val;
		print "RCON password: " . '*'x length($config->{'rcon_pass'}) . "\n";
	    }
		elsif ($config_name eq 'ftp_username') {
		$config->{'ftp_username'} = $config_val;
		print "FTP username: " . ($config->{'ftp_username'}) . "\n";
	    }
		elsif ($config_name eq 'ftp_password') {
		$config->{'ftp_password'} = $config_val;
		print "FTP password: " . '*'x length($config->{'ftp_password'}) . "\n";
	    }
	    elsif ($config_name eq 'server_logfile') {
		$config->{'server_logfile_name'} = $config_val;
		print "Server logfile name: $config->{'server_logfile_name'}\n";
		my $file;
		if ($config_val =~ /ftp:\/\/([^\/]+)\/(.+)/) {
		    # FTP url has been specified - remote FTP mode selected
		    ($ftp_host,$file,$logfile_mode) = ($1,$2,'ftp');
		    ($ftp_dirname,$ftp_basename) = (dirname($file), basename($file));
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
            elsif ($config_name eq 'affiliate_server_prenouncement') {
                push @affiliate_server_prenouncements, $config_val;
                print "Affiliate Server Prenouncement: $config_val\n";
            }
            elsif ($config_name eq 'remote_server') {
                push @remote_servers, $config_val;
                print "Remote Server: $config_val\n";
            }
	    elsif ($config_name =~ /^(audit_guid0_players|antispam|antiidle|glitch_server_mode|ping_enforcement|999_quick_kick|flood_protection|killing_sprees|bad_shots|nice_shots|first_blood|anti_vote_rush|ban_name_thieves|affiliate_server_announcements|use_passive_ftp|guid_sanity_check|use_announcements|use_responses)$/) {
		if ($config_val =~ /yes|1|on|enable/i) { $config->{$config_name} = 1; }
                else { $config->{$config_name} = 0; }
                print "$config_name: " . $config->{$config_name} . "\n";
            }
	    elsif ($config_name =~ 'interval_m[ia][nx]|banned_name_warn_message_[12]|banned_name_kick_message|max_ping|glitch_kill_kick_message|anti(spam|idle)_warn_(level|message)_[12]|anti(spam|idle)_kick_(level|message)|ftp_(username|password|refresh_time)|affiliate_server_announcement_interval') {
                $config->{$config_name} = $config_val;
                print "$config_name: " . $config->{$config_name} . "\n";
            }
	    elsif ($config_name =~ /show_(joins|game_joins|game_quits|quits|kills|headshots|timestamps|talk|rcon)/) {
		if ($config_val =~ /yes|1|on/i) { $config->{$config_name} = 1; }
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
    if (!defined($config->{'ip'})) { &die_nice("Config File: ip_address is not defined\tCheck the config file: $config_file\n"); }
    if (!defined($config->{'rcon_pass'})) { &die_nice("Config File: rcon_pass is not defined\tCheck the config file: $config_file\n"); }

    print "\nFinished parsing config: $config_file\n\n";

}
# END: load_config_file

# BEGIN: die_nice(message)
sub die_nice {
    my $message = shift;
    if ((!defined($message)) or ($message !~ /./)) { $message = 'default die_nice message.\n\n'; }
    print "\nCritical Error: $message\n\n";
	# dirty workaround, but sometimes server can drop a ftp connection or it can be lost on client side
	if ($ftpfail) {
	sleep 10;
	&ftp_connect;
	$ftpfail = 0;
	}
	elsif (!$ftpfail) {
	print "Press <ENTER> to close this program\n";
	my $who_cares = <STDIN>;
    -e $ftp_tmpFileName && unlink($ftp_tmpFileName);
    exit 1; 
	}
}
# END: die_nice

# BEGIN: open_server_logfile(logfile)
sub open_server_logfile {
    my $log_file = shift;
    if (!defined($log_file)) { &die_nice("open_server_logfile called without an argument\n"); }
    if (!-e $log_file) { &die_nice("open_server_logfile file does not exist: $log_file\n"); }
    print "Opening $log_file for reading...\n\n";
	open (LOGFILE, $log_file) or &die_nice("unable to open $log_file: $!\n");
	}
# END: open_server_logfile

# BEGIN: initialize_databases
sub initialize_databases {
    my %tables;
    my $cmd;
    my $result_code;
    # populate the list of tables already in the databases.
    $sth = $guid_to_name_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $tables{$_} = $_; }
    # The GUID to NAME database
    if ($tables{'guid_to_name'}) { print "GUID <-> NAME database brought online\n\n"; }
    else {
	print "Creating guid_to_name database...\n\n";
	$cmd = "CREATE TABLE guid_to_name (id INTEGER PRIMARY KEY, guid INT(8), name VARCHAR(64));";
	$result_code = $guid_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $guid_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code rows were inserted\n"; }
	$cmd = "CREATE INDEX guid_index ON guid_to_name (id,guid,name)";
	$result_code = $guid_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $guid_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code rows were inserted\n"; }
    }
    # The IP to GUID mapping table
    $sth = $ip_to_guid_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $tables{$_} = $_; }
    if ($tables{'ip_to_guid'}) { print "IP <-> GUID database brought online\n\n"; }
    else {
	print "Creating ip_to_guid database...\n\n";
	$cmd = "CREATE TABLE ip_to_guid (id INTEGER PRIMARY KEY, ip VARCHAR(15), guid INT(8));";
	$result_code = $ip_to_guid_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_guid_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	$cmd = "CREATE INDEX ip_to_guid_index ON ip_to_guid (id,ip,guid)";
	$result_code = $ip_to_guid_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_guid_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    # The IP to NAME mapping table
    $sth = $ip_to_name_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $tables{$_} = $_; }
    if ($tables{'ip_to_name'}) { print "IP <-> NAME database brought online\n\n"; }
    else {
	print "Creating ip_to_name database...\n\n";
	$cmd = "CREATE TABLE ip_to_name (id INTEGER PRIMARY KEY, ip VARCHAR(15), name VARCHAR(64));";
	$result_code = $ip_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	$cmd = "CREATE INDEX ip_to_name_index ON ip_to_name (id,ip,name)";
	$result_code = $ip_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    # The seen database
    $sth = $seen_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $tables{$_} = $_; }
    if ($tables{'seen'}) { print "seen database brought online\n\n"; }
    else {
	print "Creating seen database...\n\n";
	$cmd = "CREATE TABLE seen (id INTEGER PRIMARY KEY, name VARCHAR(64), time INTEGER, saying VARCHAR(128));";
	$result_code = $seen_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $seen_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	$cmd = "CREATE INDEX seen_time_saying ON seen (id,name,time,saying)";
	$result_code = $seen_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $seen_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
	# The name database
    $sth = $names_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $names_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $tables{$_} = $_; }
    if ($tables{'names'}) { print "name database brought online\n\n"; }
    else {
	print "Creating names database...\n\n";
	$cmd = "CREATE TABLE names (id INTEGER PRIMARY KEY, name VARCHAR(64));";
	$result_code = $names_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $names_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	$cmd = "CREATE INDEX names_index ON names (id,name)";
	$result_code = $names_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $names_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
	# The rank database
    $sth = $ranks_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $tables{$_} = $_; }
    if ($tables{'ranks'}) { print "ranks database brought online\n\n"; }
    else {
	print "Creating ranks database...\n\n";
	$cmd = "CREATE TABLE ranks (id INTEGER PRIMARY KEY, rank VARCHAR(64));";
	$result_code = $ranks_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ranks_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	$cmd = "CREATE INDEX ranks_index ON ranks (id,rank)";
	$result_code = $ranks_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ranks_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    # The bans database
    $sth = $bans_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $tables{$_} = $_; }
    if ($tables{'bans'}) { print "bans database brought online\n\n"; }
    else {
    print "Creating bans database...\n\n";
    $cmd = "CREATE TABLE bans (id INTEGER PRIMARY KEY, ban_time INTEGER, unban_time INTEGER, ip VARCHAR(15), guid INT(8), name VARCHAR(64));";
    $result_code = $bans_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $bans_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
    $cmd = "CREATE INDEX bans_all ON bans (id,ban_time,unban_time,ip,guid,name)";
    $result_code = $bans_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $bans_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    # The definitions database
    $sth = $definitions_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
    my @tmp;
    while (@tmp = $sth->fetchrow_array) { foreach (@tmp) { $tables{$_} = $_; } }
    if ($tables{'definitions'}) { print "definitions database brought online\n\n"; }
    else {
    print "Creating definitions database...\n\n";
    $cmd = "CREATE TABLE definitions (id INTEGER PRIMARY KEY, term VARCHAR(32), definition VARCHAR(250));";
    $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
    $cmd = "CREATE INDEX definitions_all ON definitions (id,term,definition)";
    $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    if ($tables{'cached'}) { print "cached definitions index database brought online\n\n"; }
    else {
    print "Creating cached database...\n\n";
    $cmd = "CREATE TABLE cached (id INTEGER PRIMARY KEY, term VARCHAR(32));";
    $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
    $cmd = "CREATE INDEX cached_all ON cached (id,term)";
    $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    if ($tables{'cached_definitions'}) { print "cached definitions data database brought online\n\n"; }
    else {
    print "Creating cached_definitions database...\n\n";
    $cmd = "CREATE TABLE cached_definitions (id INTEGER PRIMARY KEY, term VARCHAR(32), definition VARCHAR(250));";
    $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
    $cmd = "CREATE INDEX cached_defintions_all ON cached_definitions (id,term,definition)";
    $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
    if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    # The stats database
    $sth = $stats_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
    while (@tmp = $sth->fetchrow_array) { foreach (@tmp) { $tables{$_} = $_; } }
    if ($tables{'stats'}) { print "stats database brought online\n\n"; }
    else {
	print "Creating stats database\n\n";
	$cmd = "CREATE TABLE stats (id INTEGER PRIMARY KEY, name VARCHAR(64), kills INTEGER, deaths INTEGER, headshots INTEGER, pistol_kills INTEGER, grenade_kills INTEGER, bash_kills INTEGER, shotgun_kills INTEGER, sniper_kills INTEGER, rifle_kills INTEGER, machinegun_kills INTEGER, best_killspree INTEGER, nice_shots INTEGER, bad_shots INTEGER, first_bloods INTEGER, bomb_plants INTEGER, bomb_defuses INTEGER );";
	$result_code = $stats_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	$cmd = "CREATE INDEX stats_index ON stats (id,name,kills,deaths,headshots,pistol_kills,grenade_kills,bash_kills,shotgun_kills,sniper_kills,rifle_kills,machinegun_kills,best_killspree,nice_shots,bad_shots,first_bloods,bomb_plants,bomb_defuses)";
	$result_code = $stats_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
}
# END: initialize_databases

# BEGIN: idle_check
sub idle_check {
    my $slot;
    my $idle_for;
    print "Checking for idle players...\n";
    foreach $slot (keys %last_activity_by_slot) {
	if ($slot > 0) {
	    if (($slot ne -1) && ($last_activity_by_slot{$slot} ne 'gone')) {
		$idle_for = $time - $last_activity_by_slot{$slot};
		if ($idle_for > 120) { print "Slot $slot: $name_by_slot{$slot} has been idle for " . duration($idle_for) . "\n"; }
		if (!defined($idle_warn_level{$slot})) { $idle_warn_level{$slot} = 0; }
                if (($idle_warn_level{$slot} < 1) && ($idle_for >= $config->{'antiidle_warn_level_1'})) {
                    print "IDLE_WARN1: Idle Time for $name_by_slot{$slot} has exceeded warn1 threshold: " . duration($config->{'antiidle_warn_level_1'}) . "\n";
                    &rcon_command("say $name_by_slot{$slot} ^7" . $config->{'antiidle_warn_message_1'} . '  (idle for ' . duration($idle_for) . ')');
                    $idle_warn_level{$slot} = 1;
                }
		if (($idle_warn_level{$slot} < 2) && ($idle_for >= $config->{'antiidle_warn_level_2'})) {
		    print "IDLE_WARN2: Idle Time for $name_by_slot{$slot} has exceeded warn2 threshold: " . duration($config->{'antiidle_warn_level_2'}) . "\n";
            &rcon_command("say $name_by_slot{$slot} ^7" . $config->{'antiidle_warn_message_2'} . '  (idle for ' . duration($idle_for) . ')');
		    $idle_warn_level{$slot} = 2;
		}
		if ($idle_for >= $config->{'antiidle_kick_level'}) {
		    print "KICK: Idle Time for $name_by_slot{$slot} exceeded.\n";
		    &rcon_command("say $name_by_slot{$slot} ^7" . $config->{'antiidle_kick_message'});
            sleep 1;
		    &rcon_command("say $name_by_slot{$slot}" . '" ^7был выкинут за то что был афк слишком долго: "' . duration($idle_for));
		    sleep 1;
		    &rcon_command("clientkick $slot");
		    &log_to_file('logs/kick.log', "IDLE: $name_by_slot{$slot} was kicked for being idle");
		}
	    }
	}
    }
}
# END: idle_check

# BEGIN: chat
sub chat{
    # Relevant Globals: 
    #   $name
    #   $slot 
    #   $message
    #   $guid
    my $chatmode = shift;
    if (!defined($ignore{$slot})) { $ignore{$slot} = 0; }
    # print the message to the console
    if ($config->{'show_talk'}) {
	if ($chatmode eq 'global') { print &strip_color("GLOBAL CHAT: $name: $message\n"); }
	if ($chatmode eq 'team') { print &strip_color("TEAM CHAT: $name: $message\n"); }
	if ($chatmode eq 'private') { print &strip_color("PRIVATE CHAT: $name: $message\n"); }
	}
	if ($chatmode eq 'global') { &log_to_file('logs/chat.log', &strip_color("GLOBAL CHAT: $name: $message")); }
	if ($chatmode eq 'team') { &log_to_file('logs/chat.log', &strip_color("TEAM CHAT: $name: $message")); }
	if ($chatmode eq 'private') { &log_to_file('logs/chat.log', &strip_color("PRIVATE CHAT: $name: $message")); }
    # Anti-Spam functions
    if (($config->{'antispam'}) && (!$ignore{$slot})) {
	if (!defined($spam_last_said{$slot})) { $spam_last_said{$slot} = $message; }
	else {
	    if ($spam_last_said{$slot} eq $message) {
		if (!defined($spam_count{$slot})) { $spam_count{$slot} = 1; }
		else { $spam_count{$slot} += 1; }
		if ($spam_count{$slot} == $config->{'antispam_warn_level_1'}) { &rcon_command("say ^1$name_by_slot{$slot}^7: " . $config->{'antispam_warn_message_1'}); }
		if ($spam_count{$slot} == $config->{'antispam_warn_level_2'}) { &rcon_command("say ^1$name_by_slot{$slot}^7: " . $config->{'antispam_warn_message_2'}); }
		if (($spam_count{$slot} >= $config->{'antispam_kick_level'}) && ($spam_count{$slot} <= ( $config->{'antispam_kick_level'} + 1))) {  
		    if (&flood_protection('anti-spam-kick', 30, $slot)) { }
			else {
			&rcon_command("say ^1$name_by_slot{$slot}^7: " . $config->{'antispam_kick_message'});
			sleep 1;
			&rcon_command("clientkick $slot");
			&log_to_file('logs/kick.log', "SPAM: $name_by_slot{$slot} was kicked for spamming: $message");
		    }
        }
		print "Spam:  $name said $message repeated $spam_count{$slot} times\n";
	    }
		else {
		$spam_last_said{$slot} = $message;
		$spam_count{$slot} = 0;
	    } 
	}
    }
    # End Anti-Spam functions

    # populate the seen data
    my $is_there;
    $sth = $seen_dbh->prepare("SELECT count(*) FROM seen WHERE name=?");
    $sth->execute($name) or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
    foreach ($sth->fetchrow_array) { $is_there = $_; }
    if ($is_there) {
	# print "Updating Seen Data: $name - $time - $message\n";
	$sth = $seen_dbh->prepare("UPDATE seen SET time=?, saying=? WHERE name=?");
	$sth->execute($time,$message,$name) or &die_nice("Unable to do update\n");
    }
	else {
	# print "Adding Seen Data: $name - $time - $message\n";
	$sth = $seen_dbh->prepare("INSERT INTO seen VALUES (NULL, ?, ?, ?)");
	$sth->execute($name,$time,$message) or &die_nice("Unable to do insert\n");
    }
    # end of seen data population

    # ##################################
    # Server Response / Penalty System #
    # ##################################

    my $rule_name;
    my $penalty = 0;
    my $response = 'undefined';
    my $index;
    my $flooded = 0;

	if ($config->{'use_responses'})
	{
    # loop through all the rule regex looking for matches
    foreach $rule_name (keys %rule_regex) {
        if ($message =~ /$rule_regex{$rule_name}/i) {
            # We have a match, initiate response.
	    if (&flood_protection("chat-response-$rule_name", 30, $slot)) { $flooded = 1; }
	    else { $flooded = 0; }
            $index = $number_of_responses{$rule_name};
            if ($index) {
                $index = int(rand($index)) + 1;
                $response = $rule_response->{$rule_name}->{$index};
                $penalty = $rule_penalty{$rule_name};
		if ((!$flooded) && (!$ignore{$slot})) {
		    &rcon_command("say ^1$name^7: $response");
		    &log_to_file('logs/response.log', "Rule: $rule_name  Match Text: $message");
		}
            }
	    if ((!$flooded) && (!$ignore{$slot})) { print "Positive Match:\nRule Name: $rule_name\nPenalty: $penalty\nResponse: $response\n\n"; }
            if (!defined($penalty_points{$slot})) { $penalty_points{$slot} = $penalty; }
            elsif (!$ignore{$slot}) { $penalty_points{$slot} += $penalty; }
            if ((!$ignore{$slot})) { print "Penalty Points total for: $name:  $penalty_points{$slot}\n"; }
            if ((!$ignore{$slot}) && ($penalty_points{$slot} >= 100)) {
                &rcon_command("say ^1$name^7:^1" . '"Я думаю мы услышали достаточно, убирайся отсюда!"');
                sleep 1;
                &rcon_command("clientkick $slot");
                &log_to_file('logs/kick.log', "PENALTY: $name was kicked for exceeding their penalty points.  Last Message: $message");
            }
        }
    }
	}
    #  End of Server Response / Penalty System

    # Call Bad shot
    if (($config->{'bad_shots'}) && (!$ignore{$slot})) {
	if ($message =~ /^!?bs\W*$|^!?bad\s*shit\W*$|^!?hacks?\W*$|^!?hacker\W*$|^!?hax\W*$|^that was (bs|badshot)\W*$/i) {
	    if ((defined($last_killed_by{$slot})) && ($last_killed_by{$slot} ne 'none') && (&strip_color($last_killed_by{$slot}) ne $name)) {
		if (&flood_protection('badshot', 30, $slot)) {
		    # bad shot abuse
		    if (&flood_protection('badshot-two', 30, $slot)) { }
		    else {
			$stats_sth = $stats_dbh->prepare("UPDATE stats SET bad_shots = bad_shots + 1 WHERE name=?");
			$stats_sth->execute($name) or &die_nice("Unable to update stats\n");
		    }
		}
		else {
		    # update the Bad Shot counter.
		    $stats_sth = $stats_dbh->prepare("UPDATE stats SET bad_shots = bad_shots + 1 WHERE name=?");
		    $stats_sth->execute(&strip_color( $last_killed_by{$slot})) or &die_nice("Unable to update stats\n");	
		    &rcon_command("say " . '"Игроку"' . "^2$name" . '"^7не понравилось то как его убил^1"' . &strip_color($last_killed_by{$slot}));
		}
	    }  
	} 
    }
    # End of Bad Shot

    # Call Nice Shot
    if (($config->{'nice_shots'}) && (!$ignore{$slot})) {
	if ($message =~ /\bnice\W? (one|shot|1)\b|^n[1s]\W*$|^n[1s],/i) {
	    if ((defined($last_killed_by{$slot})) && ($last_killed_by{$slot} ne 'none') && (&strip_color($last_killed_by{$slot}) ne $name)) {
		if (&flood_protection('niceshot', 30, $slot)) {
		    # nice shot abuse
			if (&flood_protection('niceshot-two', 30, $slot)) { }
			else {
			$stats_sth = $stats_dbh->prepare("UPDATE stats SET nice_shots = nice_shots + 1 WHERE name=?");
			$stats_sth->execute($name) or &die_nice("Unable to update stats\n");
			}
		}
		else {
		    # update the Nice Shot counter.
		    $stats_sth = $stats_dbh->prepare("UPDATE stats SET nice_shots = nice_shots + 1 WHERE name=?");
		    $stats_sth->execute(&strip_color( $last_killed_by{$slot})) or &die_nice("Unable to update stats\n");
		    &rcon_command("say " . '"Игроку"' . "^2$name" . '"^7понравилось ^7то как его убил^1"' . &strip_color($last_killed_by{$slot}));
		}
	    }  
	}
    }
    # End of Nice Shot

    # Auto-define questions (my most successful if statement evar?)
    if ((!$ignore{$slot}) && ($message =~ /(.*)\?$/) or ($message =~ /^!(.*)/)){
	my $question = $1;
	my $counter = 0;
	my $sth;
	my @row;
	my @results;
	my $result;
	$sth = $definitions_dbh->prepare('SELECT definition FROM definitions WHERE term=?;');
	$sth->execute($question) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
	while (@row = $sth->fetchrow_array) {
	    print "DATABASE DEFINITION: $row[0]\n";
	    push @results, "$name^7:" . '"' . "^1$question ^3is:^2" . " $row[0]";
	}
	if ($#results ne -1) {
	    if (&flood_protection('auto-define', 30, $slot)) { }
	    else {
		foreach $result (@results) {
		    &rcon_command("say $result");
		    sleep 1;
		}
	    }
	}
    }

    # #####################
    # Check for !commands #
    # #####################

    if ((!$ignore{$slot}) && ($message =~ /^!/)) {

	# !locate (search_string)
	if ($message =~ /^!(locate|geolocate)\s+(.+)/i) {
	    if (&check_access('locate')) { &locate($2); }
	}
	elsif ($message =~ /^!(locate|geolocate)\s*$/i) {
	    if (&check_access('locate')) {
		if (&flood_protection('locate-miss', 15, $slot)) { }
        else { &rcon_command("say " . '"!locate кого?"'); }
	    }
	}
        # !ignore (search_string)
        if ($message =~ /^!ignore\s+(.+)/i) {
            if (&check_access('ignore')) { &ignore($1); }
        }
        elsif ($message =~ /^!ignore\s*$/i) {
            if (&check_access('ignore')) {
                if (&flood_protection('ignore', 30, $slot)) { }
                else { &rcon_command("say " . '"!ignore кого?"'); }
            }
        }
        # !forgive (search_string)
        if ($message =~ /^!forgive\s+(.+)/i) {
            if (&check_access('forgive')) { &forgive($1); }
        }
        elsif ($message =~ /^!forgive\s*$/i) {
            if (&check_access('forgive')) {
                if (&flood_protection('forgive', 30, $slot)) { }
                else { &rcon_command("say " . '"!forgive кого?"'); }
            }
        }
	# !seen (search_string)
	elsif ($message =~ /^!seen\s+(.+)/i) { 
	    if (&check_access('seen')) { &seen($1); }
	}
	elsif ($message =~ /^!seen\s*$/i) {
	    if (&check_access('seen')) {
		if (&flood_protection('seen-miss', 15, $slot)) { }
		else { &rcon_command("say " . '"!seen кого?"'); }
	    }
	}
	# !kick (search_string)
	elsif ($message =~ /^!kick\s+(.+)/i) {
	    if (&check_access('kick')) { &kick_command($1); }
	}
	elsif ($message =~ /^!kick\s*$/i) {
	    if (&check_access('kick')) { &rcon_command("say " . '"!kick кого?"'); }
	}
	# !tempban (search_string)
	elsif ($message =~ /^!tempban\s+(.+)\s+(\d+)/i) {
	    if (&check_access('tempban')) { &tempban_command($1,$2); }
	}
	elsif ($message =~ /^!tempban\s+(.+)/i) {
	    if (&check_access('tempban')) {
		&tempban_command($1,$tempbantime);
		}
	}
	elsif ($message =~ /^!tempban\s*$/i) {
	    if (&check_access('tempban')) { &rcon_command("say " . '"!tempban кого?"'); }
	}
	# !ban (search_string)
	elsif ($message =~ /^!ban\s+(.+)/i) {
	    if (&check_access('ban')) { &ban_command($1); }
	}
	elsif ($message =~ /^!ban\s*$/i) {
	    if (&check_access('ban')) { &rcon_command("say " . '"!ban кого?"'); }
	}
        # !unban (search_string)
        elsif ($message =~ /^!unban\s+(.+)/i) {
            if (&check_access('ban')) { &unban_command($1); }
        }
        elsif ($message =~ /^!unban\s*$/i) {
            if (&check_access('ban')) { &rcon_command("say " . '"Снять бан можно при помощи BAN ID, проверьте !lastbans чтобы узнать ID игроков которые были забанены"'); }
        }
		# !clearstats (search_string)
        elsif ($message =~ /^!clearstats\s+(.+)/i) {
            if (&check_access('clearstats')) { &clear_stats($1); }
        }
        elsif ($message =~ /^!clearstats\s*$/i) {
            if (&check_access('clearstats')) { &rcon_command("say " . '"!clearstats для кого?"'); }
        }
		# !clearnames (search_string)
        elsif ($message =~ /^!clearnames\s+(.+)/i) {
            if (&check_access('clearnames')) { &clear_names($1); }
        }
        elsif ($message =~ /^!clearnames\s*$/i) {
            if (&check_access('clearnames')) { &rcon_command("say " . '"!clearnames для кого?"'); }
        }
		# !ip (search_string)
        elsif ($message =~ /^!ip\s+(.+)/i) {
            if (&check_access('ip')) { &ip_player($1); }
        }
        elsif ($message =~ /^!ip\s*$/i) {
		if (&flood_protection('ip-self', 30, $slot)) { }
		else { &rcon_command("say " . '"IP-Адрес:"' . "^2$name_by_slot{$slot}^7 - ^3$ip_by_slot{$slot}"); }
		}
		# !id (search_string)
        elsif ($message =~ /^!id\s+(.+)/i) {
            if (&check_access('id')) { &id_player($1); }
        }
        elsif ($message =~ /^!id\s*$/i) {
		if (&flood_protection('id-self', 30, $slot)) { }
		else { &rcon_command("say " . '"ClientID:"' . "^2$name_by_slot{$slot}^7 - ^3$slot"); }
		}
		# !guid (search_string)
        elsif ($message =~ /^!guid\s+(.+)/i) {
            if (&check_access('guid')) { &guid_player($1); }
        }
        elsif ($message =~ /^!guid\s*$/i) {
		if (&flood_protection('guid-self', 30, $slot)) { }
		else { &rcon_command("say " . '"GUID:"' . "^2$name_by_slot{$slot}^7 - ^3$guid_by_slot{$slot}"); }
		}
		# !age (search_string)
        elsif ($message =~ /^!age\s+(.+)/i) {
            if (&check_access('age')) { &age_player($1); }
        }
        elsif ($message =~ /^!age\s*$/i) {
            if (&check_access('age')) { &rcon_command("say " . '"!age для кого?"'); }
        }
		# !name (search_string)
        elsif ($message =~ /^!name\s+(.+)/i) {
            if (&check_access('name')) { &name_player($1); }
        }
        elsif ($message =~ /^!name\s*$/i) {
            if (&check_access('name')) { &rcon_command("say " . '"!name для кого?"'); }
        }
		# !addname (name)
        elsif ($message =~ /^!addname\s+(.+)/i) {
            if (&check_access('addname')) { &add_name($1); }
        }
        elsif ($message =~ /^!addname\s*$/i) {
            if (&check_access('addname')) { &rcon_command("say " . '"!addname *Имя*"'); }
        }
		# !addrank (rank)
        elsif ($message =~ /^!addrank\s+(.+)/i) {
            if (&check_access('addrank')) { &add_rank($1); }
        }
        elsif ($message =~ /^!addrank\s*$/i) {
            if (&check_access('addrank')) { &rcon_command("say " . '"!addrank *Ранг*"'); }
        }
		# !clearname (name))
        elsif ($message =~ /^!clearname\s+(.+)/i) {
            if (&check_access('clearname')) { &clear_name($1); }
        }
        elsif ($message =~ /^!clearname\s*$/i) {
            if (&check_access('clearname')) { &rcon_command("say " . '"!clearname *Имя*"'); }
        }
		# !clearrank (rank)
        elsif ($message =~ /^!clearrank\s+(.+)/i) {
            if (&check_access('clearrank')) { &clear_rank($1); }
        }
        elsif ($message =~ /^!clearrank\s*$/i) {
            if (&check_access('clearrank')) { &rcon_command("say " . '"!clearrank *Ранг*"'); }
        }
		# !dbinfo (database)
        elsif ($message =~ /^!dbinfo\s+(.+)/i) {
            if (&check_access('dbinfo')) { &database_info($1); }
        }
        elsif ($message =~ /^!dbinfo\s*$/i) {
            if (&check_access('dbinfo')) { &rcon_command("say " . '"!dbinfo *База данных*"'); }
        }
		# !report (search_string)
        elsif ($message =~ /^!report\s+(.+)/i) {
            if (&check_access('report')) { &report_player($1); }
		}
		 elsif ($message =~ /^!report\s*$/i) {
            if (&check_access('report')) { &rcon_command("say " . '"!report кого?"'); }
		}
       # !define (word)
        elsif ($message =~ /^!(define|dictionary|dict)\s+(.+)/i) {
            if (&check_access('define')) {
		if (&flood_protection('define', 30, $slot)) { }
		else { &dictionary($2); }
            }
        }
		elsif ($message =~ /^!(define|dictionary|dict)\s*$/i) {
            if (&check_access('define')) {
		if (&flood_protection('dictionary-miss', 15, $slot)) { }
		else { &rcon_command("say $name_by_slot{$slot}^7:" . '"^7Что нужно добавить в словарь?"'); }
		    }
		}
	# !undefine (word)
        elsif ($message =~ /^!undefine\s+(.+)/i) {
		if (&check_access('undefine')) {
		if (&flood_protection('undefine', 30, $slot)) { }
	    my $undefine = $1;
		$sth = $definitions_dbh->prepare('SELECT count(*) FROM definitions WHERE term=?;');
		$sth->execute($undefine) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
		@row = $sth->fetchrow_array;
		$sth = $definitions_dbh->prepare('DELETE FROM definitions WHERE term=?;');
		$sth->execute($undefine) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
		if ($row[0] == 1) { &rcon_command("say " . '"^2Удалено определение для: "' . '"' . "^1$undefine"); }
		elsif ($row[0] > 1) { &rcon_command("say " . '"^2Удалено "' . "$row[0]" . '" определений для: "' . '"' . "^1$undefine"); }
		else { &rcon_command("say " . '"^2Больше нет определений для: "' . '"' . "^1$undefine");}
		}
		}
	# !stats
	elsif ($message =~ /^!stats\s*(.*)/i) {
	    my $stats_search = $1;
	    if (!defined($stats_search)) { $stats_search = ''; }
	    if (&check_access('stats')) {
		if (&check_access('peek')) { &stats($name,$stats_search); }
		else { &stats($name,''); }
		}
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
	    if (&check_access('weapon_control')) { &toggle_weapon('scr_allow_smokegrenades', '"Дымовые гранаты"', $2); }
	}
	elsif ($message =~ /^!(smokes?|smoke_grenades?|smoke_nades?)\s*$/i) {
	    if (&check_access('weapon_control')) { &rcon_command("say " . "^1$name:" . '"^7Вы можете включить^1"' . "!$1 on" . '"^7или выключить^1"' . "!$1 off"); }
	}
        # !grenades
        elsif ($message =~ /^!(nades?|grenades?|frag_grenades?|frag_nades?)\s+(.+)/i) {
            if (&check_access('weapon_control')) { &toggle_weapon('scr_allow_fraggrenades', '"Осколочные гранаты"', $2); }
        }
        elsif ($message =~ /^!(nades?|grenades?|frag_grenades?|frag_nades?)\s*$/i) {
            if (&check_access('weapon_control')) { &rcon_command("say " . "^1$name:" . '"^7Вы можете включить^1"' . "!$1 on" . '"^7или выключить^1"' . "!$1 off"); }
        }
        # !shotguns
        elsif ($message =~ /^!(shotguns?|trenchguns?|shot_guns?|trench_guns?)\s+(.+)/i) {
            if (&check_access('weapon_control')) { &toggle_weapon('scr_allow_shotgun', '"Дробовики"', $2); }
        }
        elsif ($message =~ /^!(shotguns?|trenchguns?|shot_guns?|trench_guns?)\s*$/i) {
            if (&check_access('weapon_control')) { &rcon_command("say " . "^1$name:" . '"^7Вы можете включить^1"' . "!$1 on" . '"^7или выключить^1"' . "!$1 off"); }
        }
	# !say
        elsif ($message =~ /^!say\s+(.+)/i) {
            if (&check_access('say')) { &rcon_command("say " . '"' . "$1"); }
        }
	# !rcon
        elsif ($message =~ /^!rcon\s+(.+)/i) {
		    if (&check_access('rcon')) {
			if (($1 =~ /rcon_password/mi) or ($1 =~ /killserver/mi) or ($1 =~ /quit/mi)) { }
            else { &rcon_command("$1"); }
		    }
        }
	# !broadcast
        elsif ($message =~ /^!broadcast\s+(.+)/i) {
            if (&check_access('broadcast')) { &broadcast_message($1); }
        }
    # !tell
        elsif ($message =~ /^!tell\s+([^\s]+)\s+(.*)/i) {
            if (&check_access('tell')) { &tell($1,$2); }
        }
	# !hostname
        elsif ($message =~ /^!(host ?name|server ?name)\s+(.+)/i) {
            if (&check_access('hostname')) {
			if (&flood_protection('hostname', 30, $slot)) { }
		    $server_name = $2;
            &rcon_command("sv_hostname $server_name");
			&rcon_command("say " . '"Изменяю название сервера..."' . "");
		    sleep 1;
		    &rcon_command("say ^2OK^7. " . '"Название сервера изменено на: "' . "$server_name");
            }
        }
		elsif ($message =~ /^!(host ?name|server ?name)\s*$/i) {
            if (&check_access('hostname')) {
			if (&flood_protection('hostname', 30, $slot)) { }
			$temporary = &rcon_query("sv_hostname");
            if ($temporary =~ /\"sv_hostname\" is: \"([^\"]+)\"/m) {
            $server_name = $1;
            $server_name =~ s/\^7$//;
            if ($server_name =~ /./) { &rcon_command("say " . '"Сейчас сервер называется"' . "$server_name^7," .  '"используйте !hostname чтобы изменить название сервера"'); }
            }
			}
        }
	# !reset
	elsif ($message =~ /^!reset/i) {
	    if (&check_access('reset')) {
		my $reset_slot;
		foreach $reset_slot (keys %last_activity_by_slot) {
		    $last_activity_by_slot{$reset_slot} = 'gone';
		    $idle_warn_level{$reset_slot} = 0;
		    &update_name_by_slot('SLOT_EMPTY', $reset_slot);
		    $ip_by_slot{$reset_slot} = 'not_yet_known';
		    $guid_by_slot{$reset_slot} = 0;
		    $spam_count{$reset_slot} = 0;
			$spam_last_said{$slot} = &random_pwd(6);
			$ping_by_slot{$slot} = 0;
		    $last_ping{$reset_slot} = 0;
		    $penalty_points{$reset_slot} = 0;
		    $last_killed_by{$reset_slot} = 'none';
		    $kill_spree{$reset_slot} = 0;
		    $best_spree{$reset_slot} = 0;
		    $ignore{$reset_slot} = 0;
			$fake_name_by_slot{$reset_slot} = undef;
			}
		&rcon_command("say " . '"Хорошо"' . "$name^7," . '" сбрасываю параметры..."');
	    }
	}
	# !reboot
	elsif ($message =~ /^!reboot/i) {
	    if (&check_access('reboot')) {
		&rcon_command("say " . '"Хорошо"' . "$name^7," . '" перезапускаю себя..."');
		my $restart = 'perl nanny.pl';
        exec $restart;
	    }
	}
	# !fixnames
        elsif ($message =~ /^!fixnames/i) {
            if (&check_access('fixnames')) {
			if (&flood_protection('fixnames', 30)) { }
                $sth = $guid_to_name_dbh->prepare('SELECT count(*) FROM guid_to_name;');
                $sth->execute or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
                @row = $sth->fetchrow_array;
                $sth = $guid_to_name_dbh->prepare('DELETE FROM guid_to_name;');
                $sth->execute or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
                if ($row[0] == 1) { &rcon_command("say " . '"^7Удалена одна запись из базы ^2GUID <-> NAME"'); }
                elsif ($row[0] > 1) { &rcon_command("say " . '"^7Удалено"' . "^1$row[0]^7" . '"записей из базы ^2GUID <-> NAME"'); }
				else { &rcon_command("say " . '"^7В базе данных не найдено нужных записей для удаления"'); }
                $sth = $ip_to_name_dbh->prepare('SELECT count(*) FROM ip_to_name WHERE length(name) > 31;');
                $sth->execute or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
                @row = $sth->fetchrow_array;
                $sth = $ip_to_name_dbh->prepare('DELETE FROM ip_to_name WHERE length(name) > 31;');
                $sth->execute or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
                if ($row[0] == 1) { &rcon_command("say " . '"^7Удалена одна запись из базы ^2IP <-> NAME"'); }
				elsif ($row[0] > 1) { &rcon_command("say " . '"^7Удалено"' . "^1$row[0]^7" . '"записей из базы ^2IP <-> NAME^7 которые имели слишком длинный формат"'); }
            }
        }
    	# !rank
        elsif ($message =~ /^!rank\s*$/i) {
            if (&check_access('rank')) {
			if (&flood_protection('rank', 30, $slot)) { return 1; }
	        $ranks_sth = $ranks_dbh->prepare("SELECT * FROM ranks ORDER BY RANDOM() LIMIT 1;");
            $ranks_sth->execute() or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
            @row = $ranks_sth->fetchrow_array;
	        if (!$row[0]) { &rcon_command("say " . '"К сожалению, не найдено рангов в базе данных"'); }
	        else { &rcon_command("say ^2$name_by_slot{$slot}^7:" . '"Твой ранг:"' . '"' . "^3$row[1]"); }
			}
        }
	# !version
	elsif ($message =~ /^!(version|ver)\b/i) {
	    if (&check_access('version')) {
		if (&flood_protection('version', 30)) { }
		else {
		    &rcon_command("say Nanny^7 for CoD2 version^2 $version");
		    sleep 1;
		    &rcon_command("say ^7by ^4smugllama ^7/ ^1indie cypherable ^7/ Dick Cheney");
		    sleep 1;
		    &rcon_command("say ... with additional help from: Bulli, Badrobot, and Grisu Drache - thanks!");
		    sleep 1;
			&rcon_command("say " . '"^3Downloadable at:^2 http://smaert.com/nannybot.zip"');
			sleep 1;
			&rcon_command("say " . '"Доработка и перевод - ^5V^0oro^5N"');
		    sleep 1;
		    &rcon_command("say " . '"^3Исходный код данной версии можно найти тут:^2 https://github.com/voron00/Nanny"');
		}	    
	    }
	}
    # !nextmap  (not to be confused with !rotate)
        elsif ($message =~ /^!(nextmap|next|nextlevel|next_map|next_level)\b/i) {
            if (&check_access('nextmap')) {
		if (&flood_protection('nextmap', 30, $slot)) { }
		elsif ($next_map && $next_gametype) { &rcon_command("say " . " ^2$name^7:" . '"Следующая карта будет:^3"' . $description{$next_map} .  " ^7(^2" . $description{$next_gametype} . "^7)"); }
            }
        }
	# !rotate
	elsif ($message =~ /^!rotate\b/i) {
	    if (&check_access('map_control')) {
		if ($next_map && $next_gametype) {
		&rcon_command("say " . '"^2Смена карты^7..."');
		sleep 1;
		&rcon_command('map_rotate');
	    }
	}
	}
	# !restart
	elsif ($message =~ /^!restart\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Перезагрузка карты^7..."');
		sleep 1;
		&rcon_command('map_restart');
	    }
	}
	# !fastrestart
	elsif ($message =~ /^!quickrestart|fastrestart\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Быстрая перезагрузка карты^7..."');
		sleep 1;
		&rcon_command('fast_restart');
	    }
	}
	# !voting
	elsif ($message =~ /^!(voting|vote|allowvote|allowvoting)\s+(.+)/i) {
	    if (&check_access('voting')) { &voting_command($2); }
	}
	elsif ($message =~ /^!(voting|vote|allowvote|allowvoting)\s*$/i) {
	    if (&check_access('voting')) { &rcon_command("say " . '"!voting on или !voting off ?"'); }
	}
	# !voice
	elsif ($message =~ /^!(voice|voicechat|sv_voice)\s+(.+)/i) {
	    if (&check_access('voice')) { &voice_command($2); }
	}
	elsif ($message =~ /^!(voice|voicechat|sv_voice)\s*$/i) {
	    if (&check_access('voice')) { &rcon_command("say " . '"!voice on или !voice off ?"'); }
	}
	# !killcam
	elsif ($message =~ /^!killcam\s+(.+)/i) {
	    if (&check_access('killcam')) { &killcam_command($1); }
	}
	elsif ($message =~ /^!killcam\s*$/i) {
	    if (&check_access('killcam')) { &rcon_command("say  " . '"!killcam on  ... или !killcam off ... ?"'); }
	}
    # !friendlyfire
        elsif ( ($message =~ /^!fr[ie]{1,2}ndly.?fire\s+(.+)/i) or ($message =~ /^!team[ _\-]?kill\s+(.+)/i)) {
            if (&check_access('friendlyfire')) { &friendlyfire_command($1); }
        }
        elsif ( ($message =~ /^!fr[ie]{1,2}ndly.?fire\s*$/i) or ($message =~ /^!team[ _\-]?kill\s*$/i)) {
        if (&check_access('friendlyfire')) {
		&rcon_command("say ^1$name: " . '"^7Вы можете ^1!friendlyfire ^50 ^7чтобы ВЫКЛЮЧИТЬ огонь по союзникам"');
		sleep 1;
		&rcon_command("say ^1$name: " . '"^7Вы можете ^1!friendlyfire ^51 ^7чтобы ВКЛЮЧИТЬ огонь по союзникам"');
		sleep 1; 
        &rcon_command("say ^1$name: " . '"^7Вы можете ^1!friendlyfire ^52 ^7чтобы ВКЛЮЧИТЬ огонь по союзникам с рикошетным уроном"');
		sleep 1;
        &rcon_command("say ^1$name: " . '"^7Вы можете ^1!friendlyfire ^53 ^7чтобы ВКЛЮЧИТЬ огонь по союзникам с совместным уроном"');
		sleep 1;
		my $state_string = 'unknown';
		if ($friendly_fire == 0) { $state_string = '"Огонь по союзникам в настоящий момент ВЫКЛЮЧЕН"'; }
		elsif ($friendly_fire == 1) { $state_string = '"Огонь по союзникам в настоящий момент ВКЛЮЧЕН"'; }
		elsif ($friendly_fire == 2) { $state_string = '"Огонь по союзникам в настоящий момент РИКОШЕТНЫЙ УРОН"'; }
		elsif ($friendly_fire == 3) { $state_string = '"Огонь по союзникам в настоящий момент СОВМЕСТНЫЙ УРОН"'; }
		if ($state_string ne 'unknown') { &rcon_command("say ^1$name: ^7 $state_string"); }
        }
        }
	# !glitch
	elsif ($message =~ /^!glitch\s+(.+)/i) {
	    if (&check_access('glitch')) { &glitch_command($1); }
	}
	elsif ($message =~ /^!glitch\s*$/i) {
	    if (&check_access('glitch')) { &rcon_command("say !glitch on" . '" или !glitch off ... ?"'); }
	}
	# forcerespawn
		elsif ($message =~ /^!forcerespawn\s*$/i) {
	    if (&check_access('forcerespawn')) { &rcon_command("say !forcerespawn on" . '" или !forcerespawn off?"'); }
	}
	# teambalance
		elsif ($message =~ /^!teambalance\s*$/i) {
	    if (&check_access('teambalance')) { &rcon_command("say !teambalance on" . '" или !teambalance off?"'); }
	}
	# spectatefree
		elsif ($message =~ /^!spectatefree\s*$/i) {
	    if (&check_access('spectatefree')) { &rcon_command("say !spectatefree on" . '" или !spectatefree off?"'); }
	}
        # !names (search_string)
        elsif ($message =~ /^!names\s+(.+)/i) {
            if (&check_access('names')) { &names($1); }
        }
        elsif ($message =~ /^!(names)\s*$/i) {
            if (&check_access('names')) { &rcon_command("say " . '"!names для кого?"'); }
        }
        # !uptime
        elsif ($message =~ /^!uptime\b/i) {
            if (&check_access('uptime')) {
		if (&flood_protection('uptime', 30, $slot)) { }
		else {
		    if ($uptime =~ /(\d+):(\d+)/) {
			my $duration = &duration( ( $1 * 60 ) + $2 );
			&rcon_command("say " . '"Этот сервер запущен и работает уже"' . "$duration"); }
		}
	        }
    }
	# !help
	elsif ($message =~ /^!help\b/i) {
	    if (&flood_protection('help', 30)) {}
	    else {
		if (&check_access('stats')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!stats ^7чтобы узнать свою подробную статистику"');
		    sleep 1;
		}
		if (&check_access('seen')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!seen ^5игрок ^7чтобы узнать когда он был на сервере и что говорил"');
		    sleep 1;
		}
		if (&check_access('locate')) {
		    &rcon_command("say " . '"^7Вы можете ^1!locate ^5игрок ^7чтобы узнать его приблизительное местоположение"');
		    sleep 1;
		}
		if (&check_access('lastkill')) {
            &rcon_command("say " . '"^7Вы можете использовать ^1!lastkill ^7чтобы узнать кто в последний раз вас убил"');
            sleep 1;
            }
		if (&check_access('map_control')) {		
		    &rcon_command("say " . '"^7Вы можете сменить тип игры при помощи: ^1!dm !tdm !ctf !sd !hq"');
		    sleep 1;
		    &rcon_command("say " . '"^7Вы можете ^1!restart ^7карты или ^1!rotate ^7чтобы перейти к следующей"');
		    sleep 1;
		    &rcon_command("say " . '"или: ^1!beltot !brecourt !burgundy !caen !carentan !el-alamein !moscow !leningrad !matmata !st.mereeglise !stalingrad !toujane !villers"');
		    sleep 1;
		}
		if (&check_access('kick')) {
		    &rcon_command("say " . '"^7Вы можете ^1!kick ^5игрок ^7чтобы выкинуть его с сервера"');
		    sleep 1;
		}
		if (&check_access('tempban')) {
		    &rcon_command("say " . '"^7Вы можете ^1!tempban ^5игрок ^7чтобы временно забанить игрока"');
		    sleep 1;
		}
		if (&check_access('ban')) {
		    &rcon_command("say " . '"^7Вы можете ^1!ban ^5игрок ^7чтобы навсегда забанить игрока"');
		    sleep 1;
		    &rcon_command("say " . '"^7Вы можете ^1!unban ^5игрок ^7или ^1!unban ^5banID# ^7чтобы снять бан"');
		    sleep 1;
		    &rcon_command("say " . '"^7Вы можете использовать  ^1!lastbans ^5номер ^7чтобы посмотреть список последних забаненных игроков"');
            sleep 1;
		}
		if (&check_access('voting')) {
		    &rcon_command("say " . '"^7Вы можете включить голосование ^1!voting ^5on ^7or или выключить его ^1!voting ^5off"');
		    sleep 1;
		}
		if (&check_access('killcam')) {
		    &rcon_command("say " . '"^7Вы можете включить ^1!killcam ^5on ^7или выключить ^1!killcam ^5off"');
		    sleep 1;
		}
		if (&check_access('teamkill')) {
            &rcon_command("say " . '"^7Вы можете ^1!friendlyfire ^5[0-4] ^7чтобы установить режим огня по союзникам"');
            sleep 1;
            }
		if (&check_access('fly')) {
		    &rcon_command("say " . '"^7Вы можете ^1!fly ^7чтобы выключить гравитацию на 20 секунд"');
		    sleep 1;
		}
		if (&check_access('gravity')) {
            &rcon_command("say " . '"^7Вы можете ^1!gravity ^5число ^7чтобы установить режим гравитации"');
            sleep 1;
            }
		if (&check_access('speed')) {
            &rcon_command("say " . '"^7Вы можете ^1!speed ^5число ^7чтобы установить режим скорости"');
            sleep 1;
            }
		if (&check_access('glitch')) {
		    &rcon_command("say " . '"^7Вы можете включить ^1!glitch ^5on ^7чтобы включить режим не убивания ^1!glitch ^5off ^7чтобы вернуть нормальный режим"');
		    sleep 1;
		}
		if (&check_access('names')) {
		    &rcon_command("say " . '"^7Вы можете ^1!names ^5игрок ^7чтобы узнать с какими никами он играл"');
		    sleep 1;
		}
		if (&check_access('best')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!best ^7чтобы посмотреть список лучших игроков на сервере"');
		    sleep 1;
		}
		if (&check_access('worst')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!worst ^7чтобы посмотреть список худших игроков на сервере"');
		    sleep 1;
		}
		if (&check_access('uptime')) {
		    &rcon_command("say " . '"^7Вы можете использовать  ^1!uptime ^7чтобы посмотреть сколько времени сервер работает"');
		    sleep 1;
		}
        if (&check_access('define')) {
            &rcon_command("say " . '"^7Вы можете^1!define ^5слово ^7чтобы добавить его в словарь"');
            sleep 1;
        }
		if (&check_access('version')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!version ^7чтобы узнать версию программы и авторов а также ссылки на скачивание"');
		    sleep 1;
		}
		if (&check_access('reset')) {
            &rcon_command("say " . '"^7Вы можете использовать  ^1!reset ^7чтобы сбросить параметры"');
            sleep 1;
            }
		if (&check_access('reboot')) {
            &rcon_command("say " . '"^7Вы можете использовать  ^1!reboot ^7чтобы перезапустить программу"');
            sleep 1;
            }
		if (&check_access('ignore')) {
            &rcon_command("say " . '"^7Вы можете ^1!ignore ^5игрок^7 чтобы запретить мне слушать что он сказал"');
            sleep 1;
            }
		if (&check_access('broadcast')) {
            &rcon_command("say " . '"^7Вы можете ^1!broadcast ^5сообщение ^7чтобы отправить его на другие серверы"');
            sleep 1;
            }
		if (&check_access('hostname')) {
            &rcon_command("say " . '"^7Вы можете ^1!hostname ^5Имя ^7чтобы переименовать сервер"');
            sleep 1;
            }
		if (&check_access('forgive')) {
            &rcon_command("say " . '"^7Вы можете ^1!forgive ^5игрок ^7чтобы простить игроку его выходки"');
            sleep 1;
            }
	    }
	}
	# !fly
	elsif ($message =~ /^!(fly|ufo)\b/i) {
	    if (&check_access('fly')) {
		if (&flood_protection('fly', 30, $slot)) { }
		else {
		    &rcon_command("say " . '"Летите как птицы!!!"');
		    &rcon_command("g_gravity 10");
		    sleep 20;
		    &rcon_command("g_gravity 800");
		    &rcon_command("say " . '"Думаю стоит продолжить нормальную игру"'); }
	    }
	}
        # !gravity (number)
        if ($message =~ /^!(g_gravity|gravity)\s*(.*)/i) {
            if (&check_access('gravity')) { &gravity_command($2); }
        }
        # !calc (expression)
        if ($message =~ /^!(calculater?|calc|calculator)\s+(.+)/i) {
	    my $expression = $2;
	    if  ($expression =~ /[^\d\.\+\-\/\* \(\)]/) {}
	    else { &rcon_command("say ^2$expression ^7=^1 " . eval($expression)); }
        }
		# !sin (value)
        if ($message =~ /^!sin\s+(\d+)/i) {
	    &rcon_command("say ^2sin $1 ^7=^1 " . sin($1));
		}
		# !cos (value)
        if ($message =~ /^!cos\s+(\d+)/i) {
	    &rcon_command("say ^2cos $1 ^7=^1 " . cos($1));
		}
	    # !tan (value)
        if ($message =~ /^!tan\s+(\d+)/i) {
	    &rcon_command("say ^2tan $1 ^7=^1 " . &tan($1));
		}
	    # !perl -v
        if ($message =~ /^!perl -v\b/i) {
	    &rcon_command("say $^V");
		}
		# !osinfo
        if ($message =~ /^!osinfo\b/i) {
	    &rcon_command("say $^O");
		}
    # !speed (number)
        if ($message =~ /^!(g_speed|speed)\s*(.*)/i) {
            if (&check_access('speed')) { &speed_command($2); }
        }
	# !big red button
	if ($message =~ /^!(big red button|nuke)/i) {
	    if (&check_access('nuke')) { &big_red_button_command; }
	}
	# Map Commands
	# !beltot and !farmhouse command
	elsif ($message =~ /^!beltot\b|!farmhouse\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: "' . "^3Beltot, France      ^7(mp_farmhouse)");
		sleep 1;
		&rcon_command('map mp_farmhouse');
	    }
	}
	# !villers !breakout !vb !bocage !villers-bocage
	elsif ($message =~ /^!villers\b|^!breakout\b|^!vb\b|^!bocage\b|^!villers-bocage\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на ^3Villers-Bocage, France      ^7(mp_breakout)"');
		sleep 1;
		&rcon_command('map mp_breakout');
	    }
	}
	# !brecourt
	elsif ($message =~ /^!brecourt\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3Brecourt, France"');
		sleep 1;
		&rcon_command('map mp_brecourt');
	    }
	}
	# !burgundy  (frequently misspelled, loose matching on vowels)
	elsif ($message =~ /^!b[ieu]rg[aeiou]?ndy\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3Burgundy, France"');
		sleep 1;
		&rcon_command('map mp_burgundy');
	    }
	}
	# !carentan  (frequently misspelled, loose matching on vowels)
	elsif ($message =~ /^!car[ie]nt[ao]n\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3Carentan, France"');
		sleep 1;
		&rcon_command('map mp_carentan');
	    }
	}
	# !st.mere !dawnville !eglise !st.mereeglise 
	elsif ($message =~ /^!(st\.?mere|dawnville|egli[sc]e|st\.?mere.?egli[sc]e)\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3St. Mere Eglise, France      ^7(mp_dawnville)"');
		sleep 1;
		&rcon_command('map mp_dawnville');
	    }
	}
	# !el-alamein !egypt !decoy
	elsif ($message =~ /^!(el.?alamein|egypt|decoy)\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3El Alamein, Egypt      ^7(mp_decoy)"');
		sleep 1;
		&rcon_command('map mp_decoy');
	    }
	}
	# !moscow !downtown
	elsif ($message =~ /^!(moscow|downtown)\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3Moscow, Russia      ^7(mp_downtown)"');
		sleep 1;
		&rcon_command('map mp_downtown');
	    }
	}
	# !leningrad      (commonly misspelled, loose matching) 
	elsif ($message =~ /^!len+[aeio]ngrad\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3Leningrad, Russia"');
		sleep 1;
		&rcon_command('map mp_leningrad');
	    }
	}
	# !matmata
	elsif ($message =~ /^!matmata\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3Matmata, Tunisia"');
		sleep 1;
		&rcon_command('map mp_matmata');
	    }
	}
	# !stalingrad !railyard
	elsif ($message =~ /^!(st[ao]l[ie]ngrad|railyard)\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: ^3Stalingrad, Russia      ^7(mp_railyard)"');
		sleep 1;
		&rcon_command('map mp_railyard');
	    }
	}
	# !toujane
	elsif ($message =~ /^!toujane\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: "' . "^3Toujane, Tunisia");
		sleep 1;
		&rcon_command('map mp_toujane');
	    }
	}
	# !caen  !trainstation
	elsif ($message =~ /^!(caen|train.?station)\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: "' . "^3Caen, France      ^7(mp_trainstation)");
		sleep 1;
		&rcon_command('map mp_trainstation');
	    }
	}
    # !rostov  !harbor
	elsif ($message =~ /^!(harbor|rostov)\b/i) {
	    if($cod_version eq '1.3') {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: "' . "^3Rostov, Russia      ^7(mp_harbor)");
		sleep 1;
		&rcon_command('map mp_harbor');
		}
	    }
	}
	# !rhine  !wallendar
	elsif ($message =~ /^!(rhine|wallendar)\b/i) {
	    if($cod_version eq '1.3') {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена на: "' . "^3Wallendar, Germany      ^7(mp_rhine)");
		sleep 1;
		&rcon_command('map mp_rhine');
	    }
		}
	}
	# End of map !commands
	# !time
	elsif ($message =~ /^!time\b/i) {
    if (&check_access('time')) {
	if (&flood_protection('time', 30, $slot)) { }
	&rcon_command("say " . '"^2Московское время^7:^3"' . "$time{'h:mm'} ^7|^3 $time{'dd.mm.yyyy'}");
	}
    }
	# !ragequit
	elsif ($message =~ /^!rage|rq|ragequit\b/i) {
	if (&flood_protection('rage', 30, $slot)) { }
        &rcon_command("say " . "^1$name_by_slot{$slot}" . '"^7покрыл всех матом, обиделся и вышел из игры."');
		sleep 1;
		&rcon_command("clientkick $slot");
    }
	 # !forcerespawn
			elsif ($message =~ /^!forcerespawn on\b/i) {
			if (&flood_protection('forcerespawn', 30, $slot)) { }
			if (&check_access('forcerespawn'))
            {
                &rcon_command("scr_forcerespawn 1");
				&rcon_command("say " . '"Быстрое возрождение ^2Включено"');
            }
        }
			elsif ($message =~ /^!forcerespawn off\b/i) {
			if (&flood_protection('forcerespawn', 30, $slot)) { }
			if (&check_access('forcerespawn'))
            {
                &rcon_command("scr_forcerespawn 0");
				&rcon_command("say " . '"Быстрое возрождение ^1Выключено"');
            }
        }
	 # !teambalance command
			elsif ($message =~ /^!teambalance on\b/i) {
			if (&flood_protection('teambalance', 30, $slot)) { }
			if (&check_access('teambalance'))
            {
                &rcon_command("scr_teambalance 1");
				&rcon_command("say " . '"Автобаланс команд ^2Включен"');
            }
        }
			elsif ($message =~ /^!teambalance off\b/i) {
			if (&flood_protection('teambalance', 30, $slot)) { }
			if (&check_access('teambalance'))
            {
                &rcon_command("scr_teambalance 0");
				&rcon_command("say " . '"Автобаланс команд ^1Выключен"');
            }
        }
	 # !spectatefree command
			elsif ($message =~ /^!spectatefree on\b/i) {
			if (&flood_protection('spectatefree', 30, $slot)) { }
			if (&check_access('spectatefree'))
            {
                &rcon_command("scr_spectatefree 1");
				&rcon_command("say " . '"Свободный режим наблюдения ^2Включен"');
            }
        }
			elsif ($message =~ /^!spectatefree off\b/i) {
			if (&flood_protection('spectatefree', 30, $slot)) { }
			if (&check_access('spectatefree'))
            {
                &rcon_command("scr_spectatefree 0");
				&rcon_command("say " . '"Свободный режим наблюдения ^1Выключен"');
            }
        }
	# !lastbans
	elsif ($message =~ /^!(lastbans?|recentbans?|bans|banned)\s+(\d+)/i) {
            if (&check_access('lastbans')) { &last_bans($2); }
        }
		elsif ($message =~ /^!(lastbans?|recentbans?|bans|banned)/i) {
            if (&check_access('lastbans')) { &last_bans(10); }
        }
	# !lastkill
        elsif ($message =~ /^!(last\s*kill|killedby|whokilledme|whowasthat)\s*(.*)/i) {
	    my $lastkill_search = $2;
	    if ((!defined($lastkill_search)) or ($lastkill_search eq '')) { $lastkill_search = ''; }
            if (&check_access('lastkill')) {
		if (&flood_protection('lastkill', 30, $slot)) { }
		else {
		    if (($lastkill_search ne '') && (&check_access('peek'))) {
			my @matches = &matching_users($lastkill_search);
			if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$lastkill_search"); }
			elsif ($#matches == 0) {
			    if ((defined( $last_killed_by{$matches[0]} )) && ($last_killed_by{$matches[0]} ne 'none')) {
				&rcon_command("say ^2" . $name_by_slot{$matches[0]} . '"^3 ^7был убит игроком ^1"' . $last_killed_by{$matches[0]} );
			    }
			}
			elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$lastkill_search"); }
		    }
			else {
			if ((defined( $last_killed_by{$slot} )) && ($last_killed_by{$slot} ne 'none') && (&strip_color($last_killed_by{$slot}) ne $name)) {
			    &rcon_command("say ^2$name^3:" . '"^7Вы были убиты игроком ^1"' . $last_killed_by{$slot} );
			}
		    }
		}
            }
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

# BEGIN: locate($search_string)
sub locate {
    my $search_string = shift;
    my $slot;
    my $location;
    my @matches = &matching_users($search_string);
    my $ip;
    my $guessed;
    my $spoof_match;
    if (($search_string =~ /^\.$|^\*$|^all$|^.$/i) && (&flood_protection('locate-all', 120))) { return 1; }
    if (&flood_protection('locate', 30, $slot)) { return 1; }
    foreach $slot (@matches) {
	if ($ip_by_slot{$slot}) {
	    print "MATCH: " . &strip_color($name_by_slot{$slot}) . ", IP = $ip_by_slot{$slot}\n";
	    $ip = $ip_by_slot{$slot};
	    if ($ip =~ /\?$/) {
		$guessed = 1;
		$ip =~ s/\?$//;
	    }
	    if ($ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/) {
		$location = &geolocate_ip($ip);
		if ($location =~ /,.* - .+/) {
		    if ($guessed) { $location = $name_by_slot{$slot} . '"^7вероятно зашел к нам из районов около^2"' . $location; }
		    else { $location = $name_by_slot{$slot} . '"^7зашел к нам из районов около^2"' . $location; }
		}
		else {
		    if ($guessed) { $location = $name_by_slot{$slot} . '"^7вероятно зашел к нам из^2"' . $location; }
		    else { $location = $name_by_slot{$slot} . '"^7зашел к нам из^2"' . $location; }
		}
		# location spoofing
		foreach $spoof_match (keys(%location_spoof)) {
		if (&strip_color($name_by_slot{$slot}) =~ /$spoof_match/i) { $location = $name_by_slot{$slot} . '^7' . $location_spoof{$spoof_match}; }
		}
		&rcon_command("say " . "$location");
		sleep 1;
	    }
	}
    }
    if ($search_string =~ /^console|nanny|server\b/i) {
	$location = &geolocate_ip($config->{'ip'});
	if ($location =~ /,.* - .+/) { $location = '"Этот сервер находится в районах около^2"' . $location; }
	else { $location = '"Этот сервер находится в^2"' . $location; }
	&rcon_command("say $location");
	sleep 1;
    }
	elsif ($search_string =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/) {
	my $target_ip = $1;
	$location = &geolocate_ip($target_ip);
	if ($location =~ /,.* - .+/) { $location = "^3$target_ip" . '"^7находится в районах около^2"' . $location; }
	else { $location = "^3$target_ip" . '"^7находится в^2"' . $location; }
	&rcon_command("say $location");
	sleep 1;
    }
}
# END: locate

# BEGIN: status
sub status {
    my $status = &rcon_query('status');
    print "$status\n";
    my @lines = split(/\n/,$status);
    my $line;
    my $slot;
    my $score;
    my $ping;
    my $guid;
    my $rate;
    my $qport;
    my $ip;
    my $port;
    my $lastmsg;
    my $name;
    my $colorless;
    foreach $line (@lines) {
	if ($line =~ /^map:\s+(\w+)/) { $map_name = $1; }
	if ($line =~ /^\s+(\d+)\s+(-?\d+)\s+([\dCNT]+)\s+(\d+)\s+(.*)\^7\s+(\d+)\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):([\d\-]+)\s+([\d\-]+)\s+(\d+)/) {
	    ($slot,$score,$ping,$guid,$name,$lastmsg,$ip,$port,$qport,$rate) = ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);
		# strip trailing spaces.
		$name =~ s/\s+$//;
		$name =~ s/$problematic_characters//g;
		# cache ping
	    $ping_by_slot{$slot} = $ping;
	    # cache the name
	    &update_name_by_slot($name, $slot);
	    # cache the guid
	    $guid_by_slot{$slot} = $guid;
        # cache slot to IP mappings
        $ip_by_slot{$slot} = $ip;
	    # cache the ip_to_guid mapping
	    if (($ip) && ($guid)) { &cache_ip_to_guid($ip,$guid); }
	    # cache the guid_to_name mapping
	    if (($guid) && ($name)) { &cache_guid_to_name($guid,$name); }
	    # cache the ip_to_name mapping
	    if (($ip) && ($name)) { &cache_ip_to_name($ip,$name); }
	    # cache names without color codes, too.
	    $colorless = &strip_color($name);
	    if ($colorless ne $name) {
		&update_name_by_slot($colorless, $slot);
		if (($ip) && ($colorless)) { &cache_ip_to_name($ip,$colorless); }
		if (($guid) && ($colorless)) { &cache_guid_to_name($guid,$colorless); }
	    }
	    # GUID Sanity Checking - detects when the server is not tracking GUIDs correctly.
	    if ($guid) {
		# we know the GUID is non-zero.  Is it the one we most recently saw join?
		if (($guid == $most_recent_guid) && ($slot == $most_recent_slot)) {
		    # was it recent enough to still be cached by activision?
		    if (($time - $most_recent_time) < (2 * $rconstatus_interval)) {
			# Is it time to run another sanity check?
			if (($time - $last_guid_sanity_check) > ($guid_sanity_check_interval)) { &guid_sanity_check($guid,$ip); }
		    } 
		}
	    }
		# Check for banned IP
		if ($ping ne 'CNCT' or $ping ne '999' or $ping ne 'ZMBI') { &check_banned_ip($ip,$name,$slot); }
	    # Ping-related checks. (Known Bug:  Not all slots are ping-enforced, rcon can't always see all the slots.)
	    if ($ping ne 'CNCT') {
		if ($ping eq '999') {
		    if (!defined($last_ping{$slot})) { $last_ping{$slot} = 0; }
		    if (($last_ping{$slot} eq '999') && ($config->{'ping_enforcement'}) && ($config->{'999_quick_kick'})) {
			print "PING ENFORCEMENT: 999 ping for $name\n";
			&rcon_command("say " . &strip_color($name) . '"^7был выкинут за 999 пинг"');
			sleep 1;
			&rcon_command("clientkick $slot");
			&log_to_file('logs/kick.log', "PING: $name was kicked for having a 999 ping for too long");
			}
		}
		elsif ($ping > $config->{'max_ping'}) {
		    if (!defined($last_ping{$slot})) { $last_ping{$slot} = 0; }
		    if ($last_ping{$slot} > ($config->{'max_ping'}) && ($config->{'ping_enforcement'})) {
			print "PING ENFORCEMENT: too high ping for $name\n";
			&rcon_command("say " . &strip_color($name) . '"^7был выкинут за слишком высокий пинг"' . "($ping_by_slot{$slot} | $config->{'max_ping'})");
			sleep 1;
			&rcon_command("clientkick $slot");
			&log_to_file('logs/kick.log', "$name was kicked for having too high ping. ($ping_by_slot{$slot} | $config->{'max_ping'})");
			}
		}
		# we need to remember this for the next ping we check.
		$last_ping{$slot} = $ping;
		}
	    # End of Ping Checks.
	}
    }
	# BEGIN: IP Guessing - if we have players who we don't get IP's with status, try to fake it.
    foreach $slot (sort { $a <=> $b } keys %guid_by_slot) {
	if ($slot >= 0) {
	    if ($guid_by_slot{$slot}) {
		$sth = $ip_to_guid_dbh->prepare("SELECT ip FROM ip_to_guid WHERE guid=? ORDER BY id DESC LIMIT 1");
	    if ((!defined($ip_by_slot{$slot})) or ($ip_by_slot{$slot} eq 'not_yet_known')) {
		$ip_by_slot{$slot} = 'unknown';
		$sth->execute($guid_by_slot{$slot}) or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
		while (@row = $sth->fetchrow_array) {
		$ip_by_slot{$slot} = $row[0] . '?';
		print "Guessed an IP by GUID for: $name_by_slot{$slot} = $ip_by_slot{$slot} \n";
		}
	    }
		}
		elsif (!$guid_by_slot{$slot}) {
		$sth = $ip_to_name_dbh->prepare("SELECT ip FROM ip_to_name WHERE name=? ORDER BY id DESC LIMIT 1");
	    if ((!defined($ip_by_slot{$slot})) or ($ip_by_slot{$slot} eq 'not_yet_known')) {
		$ip_by_slot{$slot} = 'unknown';
		$sth->execute($name_by_slot{$slot}) or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
		while (@row = $sth->fetchrow_array) {
		$ip_by_slot{$slot} = $row[0] . '?';
		print "Guessed an IP by NAME for: $name_by_slot{$slot} = $ip_by_slot{$slot} \n";
		}
	    }
		}
	}
    }
    # END:  IP Guessing from cache
}
# END: status

# BEGIN: Check for Banned IP
sub check_banned_ip {
    my $ip = shift;
	my $name = shift;
	my $slot = shift;
    $sth = $bans_dbh->prepare("SELECT * FROM bans WHERE ip=? AND unban_time > $time ORDER BY id DESC LIMIT 1");
	$sth->execute($ip);
	while (@row = $sth->fetchrow_array) {
	if ($row[3] ne 'undefined') {
    sleep 1;
	&rcon_command("say " . &strip_color($name) . "^7: " . '"Вы забанены. Вы не можете остатся на этом сервере"');
	sleep 1;
	&rcon_command("say $row[5]^7:" . '"Был забанен"' . scalar(localtime($row[1])) . " - (BAN ID#: ^1$row[0]^7)");
	sleep 1;
	if ($row[2] == 2125091758) { &rcon_command("say " . &strip_color($name) . "^7: " . '"^7У вас перманентный бан."'); }
	else { &rcon_command("say " . &strip_color($name) . "^7:" . '"Вы будете разбанены через"' . &duration(($row[2]) - $time)); }
	sleep 1;
	&rcon_command("clientkick $slot");
	&log_to_file('logs/kick.log', "KICK: BANNED: $name was kicked - banned IP: $ip ($row[3]) - (BAN ID#: $row[0])");
	$last_rconstatus = $time;
	}
	}
}
# END: Check for Banned IP

# BEGIN: Check for Banned GUID
sub check_banned_guid {
    my $guid = shift;
	my $name = shift;
	my $slot = shift;
    $sth = $bans_dbh->prepare("SELECT * FROM bans WHERE guid=? AND unban_time > $time ORDER BY id DESC LIMIT 1");
	$sth->execute($guid);
	while (@row = $sth->fetchrow_array) {
	if ($row[4] ne '12345678') {
    sleep 1;
	&rcon_command("say " . &strip_color($name) . "^7: " . '"Вы забанены. Вы не можете остатся на этом сервере"');
	sleep 1;
	&rcon_command("say $row[5]^7:" . '"Был забанен"' . scalar(localtime($row[1])) . " - (BAN ID#: ^1$row[0]^7)");
	sleep 1;
	if ($row[2] == 2125091758) { &rcon_command("say " . &strip_color($name) . "^7: " . '"^7У вас перманентный бан."'); }
	else { &rcon_command("say " . &strip_color($name) . "^7:" . '"Вы будете разбанены через"' . &duration(($row[2]) - $time)); }
	sleep 1;
	&rcon_command("clientkick $slot");
	&log_to_file('logs/kick.log', "KICK: BANNED: $name was kicked - banned GUID: $guid ($row[4]) - (BAN ID#: $row[0])");
	$last_rconstatus = $time;
	}
	}
}
# END: Check for Banned GUID

# BEGIN: rcon_command($command)
sub rcon_command {
    my ($command) = @_;
	my $error;
    # odd bug regarding double slashes.
    $command =~ s/\/\/+/\//g;
	$rcon->execute($command);
	&log_to_file('logs/rcon.log', "RCON: executed command: $command");
    if ($config->{'show_rcon'}) {
	$command =~ s/\^\d//g;
	print "RCON: $command\n";
	}
    sleep 1;
    if ($error = $rcon->error) {
	# rcon timeout happens after the object has been in use for a long while.
	# Try rebuilding the object
	if ($error eq 'Rcon timeout') {
	print "rebuilding rcon object\n";
	$rcon = new KKrcon (Host => $config->{'ip'}, Port => $config->{'port'}, Password => $config->{'rcon_pass'}, Type => 'old');
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
    if ($config->{'show_rcon'}) {
	$command =~ s/\^\d//g;
	print "RCON: $command\n"; 
	}
    sleep 1; 
    if ($error = $rcon->error) {
	# rcon timeout happens after the object has been in use for a long while.
    # Try rebuilding the object
    if ($error eq 'Rcon timeout') {
    print "rebuilding rcon object\n";
    $rcon = new KKrcon (Host => $config->{'ip'}, Port => $config->{'port'}, Password => $config->{'rcon_pass'}, Type => 'old');
    }
	else { print "WARNING: rcon_command error: $error\n"; }
	return $result;
	}
    else { return $result; }
}
# END: rcon_query

# BEGIN: geolocate_ip
sub geolocate_ip {
    my $ip = shift;
    my $metric = 0;
    if (!$ip) { return '"Не указан IP-Адрес"'; }
	if ($ip =~ /^192\.168\.|^10\.|localhost|127.0.0.1|loopback|^169\.254\./) { return '"^2своей локальной сети"'; }
    if ($ip !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) { return '"Неверный IP-Адрес:"' . "$ip"; }
    my $gi = Geo::IP->open("Geo/GeoLiteCity.dat", GEOIP_STANDARD);
    my $record = $gi->record_by_addr($ip);
	my $geo_ip_info;
	if (!$record) { return '"ниоткуда..."'; }
	# debugging
    if (defined($record->country_code)) { print "\n\tCountry Code: " . $record->country_code . "\n"; }
    if (defined($record->country_code3)) { print "\tCountry Code 3: " . $record->country_code3 . "\n"; }
    if (defined($record->country_name)) { print "\tCountry Name: " . $record->country_name . "\n"; }
    if (defined($record->region)) { print "\tRegion: " . $record->region . "\n"; }
	if (defined($record->region_name)) { print "\tRegion Name: " . $record->region_name . "\n"; }
    if (defined($record->city)) { print "\tCity: " . $record->city . "\n"; }
    if (defined($record->postal_code)) { print "\tPostal Code: " . $record->postal_code . "\n"; }
    if (defined($record->latitude)) { print "\tLattitude: " . $record->latitude . "\n"; }
    if (defined($record->longitude)) { print "\tLongitude: " . $record->longitude . "\n"; }
	if (defined($record->time_zone)) { print "\tTime Zone: " . $record->time_zone . "\n"; }
    if (defined($record->area_code)) { print "\tArea Code: " . $record->area_code . "\n"; }
	if (defined($record->continent_code)) { print "\tContinent Code: " . $record->continent_code . "\n"; }
	if (defined($record->metro_code)) { print "\tMetro Code " . $record->metro_code . "\n\n"; }
	# end of debugging
    if ($record->city) {
        # we know the city
        if ($record->region_name) {
            # and we know the region name
            if ($record->city ne $record->region_name) {
                # the city and region name are different, all three are relevant.
                $geo_ip_info = $record->city . '^7,^2 ' . $record->region_name . ' - ' . $record->country_name;
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
	elsif ($record->country_code) {
        # How about a 2 letter country code at least?
        $geo_ip_info = $record->country_code;
    }
	else {
        # I give up.
        $geo_ip_info = '"ниоткуда"';
    }
    if (($record->country_code) && ($record->country_code eq 'US')) { $metric = 0 }
    else { $metric = 1; }
    # GPS Coordinates
    if (($config->{'ip'} !~ /^192\.168\.|^10\.|localhost|127.0.0.1|loopback|^169\.254\./)) {
	if (($record->latitude) && ($record->longitude) && ($record->latitude =~ /\d/)) {
	    my ($player_lat, $player_lon) = ($record->latitude, $record->longitude);
	    # gps coordinates are defined for this IP.
	    # now make sure we have coordinates for the server.
	    $record = $gi->record_by_name($config->{'ip'});
	    if (($record->latitude) && ($record->longitude) && ($record->latitude =~ /\d/)) {
		my ($home_lat, $home_lon) = ($record->latitude, $record->longitude);
		# Workaround for my server
		if (($config->{'ip'}) eq '62.140.250.90') {
		$home_lat = 55.7522;
		$home_lon = 37.6155;
		}
		my $obj = Geo::Inverse->new; 
		my $dist = $obj->inverse($player_lat, $player_lon , $home_lat, $home_lon);
		if ($ip ne $config->{'ip'}) {
		if ($metric) {
                    $dist = int($dist/1000);
					# Workaround for standard 'europe' lat and lon
					if ($player_lat eq '60.0000' && $player_lon eq '100.0000') { $geo_ip_info .= '^7,"расстояние до сервера неизвестно"'; }
					else { $geo_ip_info .= "^7, ^1$dist^7" . '"километров до сервера"'; }
		}
		else {
		            $dist = int($dist/1609.344);
					# Workaround for standard 'europe' lat and lon
					if ($player_lat eq '60.0000' && $player_lon eq '100.0000') { $geo_ip_info .= '^7,"расстояние до сервера неизвестно"'; }
					else { $geo_ip_info .= "^7, ^1$dist^7" . '"миль до сервера"'; }
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
    # idiot gates
    if (!defined($guid)) { &die_nice("cache_guid_to_name was called without a guid number\n"); }
	elsif ($guid !~ /^\d+$/) { &die_nice("cache_guid_to_name guid was not a number: |$guid|\n"); }
	elsif (!defined($name)) { &die_nice("cache_guid_to_name was called without a name\n"); }  
    if ($guid) {
	# only log this if the guid isn't zero
	$sth = $guid_to_name_dbh->prepare("SELECT count(*) FROM guid_to_name WHERE guid=? AND name=?");
	$sth->execute($guid,$name) or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
	@row = $sth->fetchrow_array;
	if ($row[0]) { }
	else {
	    &log_to_file('logs/guid.log', "Caching GUID to NAME mapping: $guid - $name");
	    print "Caching GUID to NAME mapping: $guid - $name\n";
	    $sth = $guid_to_name_dbh->prepare("INSERT INTO guid_to_name VALUES (NULL, ?, ?)");
	    $sth->execute($guid, $name) or &die_nice("Unable to do insert\n");
	}
    }
}
# END: cache_guid_to_name

# BEGIN: cache_ip_to_guid($ip,$guid)
sub cache_ip_to_guid {
    my $ip = shift;
    my $guid = shift;
    # idiot gates
    if (!defined($guid)) { &die_nice("cache_ip_to_guid was called without a guid number\n"); }
	elsif ($guid !~ /^\d+$/) { &die_nice("cache_ip_to_guid guid was not a number: |$guid|\n"); }
	elsif (!defined($ip)) { &die_nice("cache_ip_to_guid was called without an ip\n"); }
    if ($guid) {
	# only log this if the guid isn't zero
	$sth = $ip_to_guid_dbh->prepare("SELECT count(*) FROM ip_to_guid WHERE ip=? AND guid=?");
	$sth->execute($ip,$guid) or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
	@row = $sth->fetchrow_array;
	if ($row[0]) { }
	else {
	    &log_to_file('logs/guid.log', "New IP to GUID mapping: $ip - $guid");
	    print "New IP to GUID mapping: $ip - $guid\n";
	    $sth = $ip_to_guid_dbh->prepare("INSERT INTO ip_to_guid VALUES (NULL, ?, ?)");
	    $sth->execute($ip, $guid) or &die_nice("Unable to do insert\n");
	}
    }
}
# END: cache_ip_to_guid

# BEGIN: cache_ip_to_name($ip,$name)
sub cache_ip_to_name {
    my $ip = shift;
    my $name = shift;
    # idiot gates
    if (!defined($name)) { &die_nice("cache_ip_to_name was called without a name\n"); }
	elsif (!defined($ip)) { &die_nice("cache_ip_to_name was called without an ip\n"); }
    $sth = $ip_to_name_dbh->prepare("SELECT count(*) FROM ip_to_name WHERE ip=? AND name=?");
    $sth->execute($ip,$name) or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { }
    else {
	&log_to_file('logs/guid.log', "Caching IP to NAME mapping: $ip - $name");
	print "Caching IP to NAME mapping: $ip - $name\n"; 
	$sth = $ip_to_name_dbh->prepare("INSERT INTO ip_to_name VALUES (NULL, ?, ?)");
	$sth->execute($ip, $name) or &die_nice("Unable to do insert\n");
    }
}
# END: cache_ip_to_name

# BEGIN: seen($search_string)
sub seen {
    my $search_string = shift;
    $sth = $seen_dbh->prepare("SELECT name,time,saying FROM seen WHERE name LIKE ? ORDER BY time DESC LIMIT 5");
    $sth->execute("\%$search_string\%") or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
    if (&flood_protection('seen', (10 + ($sth->rows * 5)), $slot)) { return 1; }
    while (@row = $sth->fetchrow_array) {
	&rcon_command("say " . " $row[0] " . '" ^7был замечен на сервере "' . "" . duration($time - $row[1]) . "" . '" назад, и сказал:"' . '"' . " $row[2]");
	sleep 1;
    }
}
# END: seen

# BEGIN: log_to_file($file, $message)
sub log_to_file {
    my ($logfile,$msg) = @_;
    open LOG, ">> $logfile" or return 0;
    print LOG "$timestring: $msg\n";
    close LOG;
}
# END: log_to_file

# BEGIN: stats($search_string)
sub stats {
    if (&flood_protection('stats', 30)) { return 1; }
    my $name = shift;
    my $search_string = shift;
    if ($search_string ne '') {
	my @matches = &matching_users($search_string);
	if ($#matches == 0) { $name = $name_by_slot{$matches[0]}; }
	elsif ($#matches > 0) {
	    &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string");
	    return 1;
	}
    }
    if (($name eq 'Unknown Soldier') or ($name eq 'UnnamedPlayer')) { &rcon_command("say $name:" . '"Прости, но я не веду статистику для неизвестных! Смени свой ник если хочешь чтобы я записывала твою статистику."'); }
	else {
    my $stats_msg = '"Статистика^2"' . "$name^7:";
    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE name=?");
    $stats_sth->execute($name) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    @row = $stats_sth->fetchrow_array;
    if ((!$row[0]) && ($name ne &strip_color($name))) {
	$stats_sth->execute(&strip_color($name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	@row = $stats_sth->fetchrow_array;
    }
    if ($row[0]) {
	# kills, deaths, headshots
	my $kills = $row[2];
	my $deaths = $row[3];
	my $headshots = $row[4];
	$stats_msg .= " ^2$kills" . '"^7убийств,"' . "^1$deaths" . '"^7смертей,"' . "^3$headshots" . '"^7хедшотов,"';
	# k2d_ratio
	if ($row[2] && $row[3]) {
	    my $k2d_ratio = int($row[2] / $row[3] * 100) / 100;
	    $stats_msg .= "^8$k2d_ratio^7" . '"^7к/д соотношение,"';
	}
	# headshot_percent
	if ($row[2] && $row[4]) {
	    my $headshot_percent = int($row[4] / $row[2] * 10000) / 100;
	    $stats_msg .= "^3$headshot_percent" . '"^7проц. хедшотов"';
	}
    &rcon_command("say $stats_msg");
    sleep 1; 
    $stats_msg = '"Статистика^2"' . "$name^7:";
	# pistol_ratio,grenade_ratio,bash_ratio
    if ($row[2]) {
	my $pistol_ratio = ($row[5]) ? int($row[5] / $row[2] * 10000) / 100 : 0;
	my $grenade_ratio = ($row[6]) ? int($row[6] / $row[2] * 10000) / 100 : 0;
	my $bash_ratio = ($row[7]) ? int($row[7] / $row[2] * 10000) / 100 : 0;
	$stats_msg .= " ^9$pistol_ratio" . '"^7пистолетов,"' . "^9$grenade_ratio" . '"^7гранат,"' . "^9$bash_ratio" . '"^7ближнего боя"';
	if (($row[5]) or ($row[6]) or ($row[7])) {
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
	# shotgun_ratio,sniper_ratio,rifle_ratio,machinegun_ratio
	$stats_msg = '"Статистика^2"' . "$name^7:";
	my $shotgun_ratio = (($row[8]) && ($row[2])) ? int($row[8] / $row[2] * 10000) / 100 : 0;
    my $sniper_ratio = (($row[9]) && ($row[2])) ? int($row[9] / $row[2] * 10000) / 100 : 0;
    my $rifle_ratio = (($row[10]) && ($row[2])) ? int($row[10] / $row[2] * 10000) / 100 : 0;
	my $machinegun_ratio = (($row[11]) && ($row[2])) ? int($row[11] / $row[2] * 10000) / 100 : 0;
    $stats_msg .= " ^7^9$shotgun_ratio" . '"^7дробовиков,"' . "^9$sniper_ratio" . '"^7снайп.винтовок,"' . "^9$rifle_ratio" . '"^7винтовок,"' . "^9$machinegun_ratio" . '"^7автоматов"';
	if (($row[8]) or ($row[9]) or ($row[10]) or ($row[11])) {
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
    # best_killspree
	my $best_killspree = $row[12];
	if ($best_killspree && ($config->{'killing_sprees'})) {
	    $stats_msg = '"Статистика^2"' . "$name^7:";
	    $stats_msg .= '"Лучшая серия убийств -^6"' . "$best_killspree";
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
	# nice_shots
	my $nice_shots = $row[13];
	my $niceshot_ratio = (($row[13]) && ($row[2])) ? int($row[13] / $row[2] * 10000) / 100 : 0;
	if (($nice_shots) && ($config->{'nice_shots'})) {
	    $stats_msg = '"Статистика^2"' . "$name^7:";
	    $stats_msg .= '"Понравившихся убийств:"' . "^2$row[13] ^7(^2$niceshot_ratio" . '"^7процентов)"';
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
    # bad_shots
	my $bad_shots = $row[14];
	my $badshot_ratio = (($row[14]) && ($row[2])) ? int($row[14] / $row[2] * 10000) / 100 : 0;
	if (($bad_shots) && ($config->{'bad_shots'})) {
	    $stats_msg = '"Статистика^2"' . "$name^7:";
	    $stats_msg .= '"Не понравившихся убийств:"' . "^1$row[14] ^7(^1$badshot_ratio" . '"^7процентов)"';
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
	# first_bloods
	my $first_bloods = $row[15];
	if (($first_bloods) && ($config->{'first_blood'})) {
	    $stats_msg = '"Статистика^2"' . "$name^7:";
	   $stats_msg .= '"Первой крови:"' . "^1$first_bloods";
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
	if ($game_type eq 'sd') {
	# bomb_plants
	my $bomb_plants = $row[16];
	if ($bomb_plants) {
	    $stats_msg = '"Статистика^2"' . "$name^7:";
	    $stats_msg .= '"Взрывчатки заложено:"' . "^4$bomb_plants";
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
	# bomb_defuses
	my $bomb_defuses = $row[17];
	if ($bomb_defuses) {
	    $stats_msg = '"Статистика^2"' . "$name^7:";
	    $stats_msg .= '"Взрывчатки обезврежено:"' . "^5$bomb_defuses";
	    &rcon_command("say $stats_msg");
	    sleep 1;
	}
	}
	}
	}
    else {
	&rcon_command("say " . '"Не найдено статистики для:"' . "$name");
	$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)");
	$stats_sth->execute($name, 0, 0, 0) or &die_nice("Unable to do insert\n");
    }
	}
}
# END: stats

# BEGIN: check_access($attribute_name)
sub check_access {
    my $attribute = shift;
	my $value;

    if (!defined($attribute)) { &die_nice("check_access was called without an attribute"); }
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
				if ($ip_by_slot{$slot} =~ /\?$/) { print "Refusing to authenticate a guessed IP address\n"; }
				else {
				    print "disabled command $attribute authenticated by wildcard IP override access: $value\n";
				    return 1;
				}
			    }
			}
			else { print "\nWARNING: unrecognized $attribute access directive:  $value\n\n"; }
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
		    if ($ip_by_slot{$slot} =~ /\?$/) { print "Refusing to authenticate a guessed IP address\n"; }
		    else {
			print "$attribute command authenticated by wildcard IP: $value\n";
			return 1;
		    }
		}
	    }
		else { print "\nWARNING: unrecognized access directive:  $value\n\n"; }
	}
    }
    # Since nothing above was a match...
    # Check to see if they have global access to all commands
    if ((defined($config->{'auth'}->{'everything'})) && ($attribute ne 'disabled')) {
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
		    if ($ip_by_slot{$slot} =~ /\?$/) { print "Refusing to authenticate a guessed IP address\n"; }
		    else {
			print "global admin access for $attribute authenticated by wildcard IP: $value\n";
			return 1;
		    }
		}
	    }
		else { print "\nWARNING: unrecognized access directive:  $value\n\n"; }
	}
    }
    return 0;
}
# END:  check_access

sub sanitize_regex {
    my $search_string = shift;
    if (!defined($search_string)) {
	print "WARNING: sanitize_regex was not passed a string\n";
	return '';
    }

    if (($search_string eq '*') or ($search_string eq '.') or ($search_string eq 'all')) { return '.'; }

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

sub matching_users {
    # a generic function to do string matches on active usernames
    #  returns a list of slot numbers that match.
    my $search_string = shift;
    if ($search_string =~ /^\/(.+)\/$/) { $search_string = $1; }
    else { $search_string = &sanitize_regex($search_string); }
    my $key;
    my @matches;
    foreach $key (keys %name_by_slot) {
	if (($name_by_slot{$key} =~ /$search_string/i) or (&strip_color($name_by_slot{$key}) =~ /$search_string/i)) {
	print "MATCH: $name_by_slot{$key}\n";
	push @matches, $key;
	}
    }
    if ($#matches == -1) {
	foreach $key (keys %name_by_slot) {
	if (&strip_color(&strip_color($name_by_slot{$key})) =~ /$search_string/i) {
    print "MATCH: $name_by_slot{$key}\n";
	push @matches, $key;}
	}
    }
    return @matches;
}

# BEGIN: !ignore($search_string)
sub ignore {
    my $search_string = shift;
    my $key;
    if ($search_string =~ /^\#(\d+)$/) {
    my $slot = $1;
    &rcon_command("say ^2$name_by_slot{$slot}" . '" ^7теперь будет игнорироватся."');
	$ignore{$slot} = 1;
    &log_to_file('logs/admin.log', "!IGNORE: $name_by_slot{$slot} was ignored by $name - GUID $guid - (Search: $search_string)");
    return 0;
	}
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
    &rcon_command("say ^2$name_by_slot{$matches[0]}" . '"^7теперь будет игнорироватся."');
    $ignore{$matches[0]} = 1;
    &log_to_file('logs/admin.log', "!IGNORE: $name_by_slot{$matches[0]} was ignored by $name - GUID $guid - (Search: $search_string)");
	}
    elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !forgive($search_string)
sub forgive {
    my $search_string = shift;
    my $key;
    if ($search_string =~ /^\#(\d+)$/) {
    my $slot = $1;
    &rcon_command("say ^2$name_by_slot{$slot}" . '"^7пообещал вести себя хорошо и был прощен админом"');
    $ignore{$slot} = 0;
	$idle_warn_level{$slot} = 0;
	$last_activity_by_slot{$slot} = $time;
	$penalty_points{$slot} = 0;
    &log_to_file('logs/admin.log', "!FORGIVE: $name_by_slot{$slot} was forgiven by $name - GUID $guid - (Search: $search_string)");
    return 0;
	}
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
    &rcon_command("say ^2$name_by_slot{$matches[0]}" . '"^7пообещал вести себя хорошо и был прощен админом"');
    $ignore{$matches[0]} = 0;
	$idle_warn_level{$matches[0]} = 0;
    $last_activity_by_slot{$matches[0]} = $time;
    $penalty_points{$matches[0]} = 0;
    &log_to_file('logs/admin.log', "!FORGIVE: $name_by_slot{$matches[0]} was forgiven by $name - GUID $guid - (Search: $search_string)");
	}
    elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !clearstats($search_string)
sub clear_stats {
if (&flood_protection('clearstats', 30, $slot)) { return 1; }
    my $search_string = shift;
    my $victim;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$victim = $name_by_slot{$matches[0]};
	$sth = $stats_dbh->prepare('DELETE FROM stats where name=?;');
    $sth->execute($victim) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	$sth->execute(&strip_color($victim)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say " . '"Удалена статистика для:"' . "$victim");
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !clearnames($search_string)
sub clear_names {
if (&flood_protection('clearnames', 30, $slot)) { return 1; }
    my $search_string = shift;
    my $victim_guid;
	my $victim_name;
	my $victim_ip;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$victim_guid = $guid_by_slot{$matches[0]};
	$victim_name = $name_by_slot{$matches[0]};
	$victim_ip = $ip_by_slot{$matches[0]};
	# Strip '?' if guessed ip
	if ($victim_ip =~ /\?$/) { $victim_ip =~ s/\?$//; }
	$sth = $guid_to_name_dbh->prepare('DELETE FROM guid_to_name where guid=?;');
    $sth->execute($victim_guid) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	$sth = $ip_to_name_dbh->prepare('DELETE FROM ip_to_name where ip=?;');
    $sth->execute($victim_ip) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say " . '"Удалены имена для:"' . "$victim_name");
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !report($search_string)
sub report_player {
    if (&flood_protection('report_player', 30)) { return 1; }
    my $search_string = shift;
    my $target_player;
	my $target_player_guid;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$target_player = $name_by_slot{$matches[0]};
	$target_player_guid = $guid_by_slot{$matches[0]};
	&rcon_command("say " . '"Жалоба на игрока"' . "$target_player" . '"^7отправлена."');
    &log_to_file('logs/report.log', "!report: $name_by_slot{$slot} - GUID $guid reported player $target_player - GUID $target_player_guid  via the !report command. (Search: $search_string)");
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !ip($search_string)
sub ip_player {
    if (&flood_protection('ip_command', 30, $slot)) { return 1; }
    my $search_string = shift;
	my $slot;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$slot = $matches[0];
	&rcon_command("say " . '"IP-Адрес:"' . "^2$name_by_slot{$slot}^7 - ^3$ip_by_slot{$slot}");
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !id($search_string)
sub id_player {
    if (&flood_protection('id_command', 30, $slot)) { return 1; }
    my $search_string = shift;
	my $slot;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$slot = $matches[0];
	&rcon_command("say " . '"ClientID:"' . "^2$name_by_slot{$slot}^7 - ^3$slot");
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !guid($search_string)
sub guid_player {
    if (&flood_protection('guid_command', 30, $slot)) { return 1; }
    my $search_string = shift;
	my $slot;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$slot = $matches[0];
	&rcon_command("say " . '"GUID:"' . "^2$name_by_slot{$slot}^7 - ^3$guid_by_slot{$slot}");
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !age($search_string)
sub age_player {
    if (&flood_protection('age_command', 30, $slot)) { return 1; }
    my $search_string = shift;
	my $age = 10 + int(rand(25 - 5));
	my $slot;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$slot = $matches[0];
	if ($age >= 10 && $age <= 20 or $age >= 25 && $age <= 30) { &rcon_command("say " . '"Возраст игрока"' . "^2$name_by_slot{$slot}^7 - ^3$age" . '"^7лет"'); }
	elsif ($age == 21 or $age == 31) { &rcon_command("say " . '"Возраст игрока"' . "^2$name_by_slot{$slot}^7 - ^3$age" . '"^7год"'); }
	else { &rcon_command("say " . '"Возраст игрока"' . "^2$name_by_slot{$slot}^7 - ^3$age" . '"^7года"'); }
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !addname($name)
sub add_name {
    if (&flood_protection('addname', 30, $slot)) { return 1; }
	my $name = shift;
	if (!defined($name)) { &die_nice("!addname was called without a name\n"); }
	$sth = $names_dbh->prepare("SELECT count(*) FROM names WHERE name=?");
	$sth->execute($name) or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	@row = $sth->fetchrow_array;
	if ($row[0]) { &rcon_command("say " . '"Имя"' . '"' . "^2$name" . '"' . '"^7уже есть в базе данных"'); }
	else {
	    $sth = $names_dbh->prepare("INSERT INTO names VALUES (NULL, ?)");
	    $sth->execute($name) or &die_nice("Unable to do insert\n");
		&rcon_command("say " . '"Имя"' . '"' . "^2$name" . '"' . '"^7добавлено в базу данных"');
	}
}

# BEGIN: !addrank($rank)
sub add_rank {
    if (&flood_protection('addrank', 30, $slot)) { return 1; }
	my $rank = shift;
	if (!defined($rank)) { &die_nice("!addrank was called without a rank\n"); }
	$sth = $ranks_dbh->prepare("SELECT count(*) FROM ranks WHERE rank=?");
	$sth->execute($rank) or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
	@row = $sth->fetchrow_array;
	if ($row[0]) { &rcon_command("say " . '"Ранг"' . '"' . "^2$rank" . '"' . '"^7уже есть в базе данных"'); }
	else {
	    $sth = $ranks_dbh->prepare("INSERT INTO ranks VALUES (NULL, ?)");
	    $sth->execute($rank) or &die_nice("Unable to do insert\n");
		&rcon_command("say " . '"Ранг"' . '"' . "^2$rank" . '"' . '"^7добавлен в базу данных"');
	}
}

# BEGIN: !clearname($name)
sub clear_name {
    if (&flood_protection('clearname', 30, $slot)) { return 1; }
	my $name = shift;
	if (!defined($name)) { &die_nice("!clearname was called without a name\n"); }
	$sth = $names_dbh->prepare("SELECT count(*) FROM names WHERE name=?");
	$sth->execute($name) or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	@row = $sth->fetchrow_array;
	if ($row[0]) {
	$sth = $names_dbh->prepare("DELETE FROM names WHERE name=?");
	$sth->execute($name) or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	&rcon_command("say " . '"Имя"' . '"' . "^2$name" . '"' . '"^7удалено из базы данных"');
	}
	else { &rcon_command("say " . '"Имя"' . '"' . "^2$name" . '"' . '"^7не найдено в базе данных"'); }
}

# BEGIN: !clearrank($rank)
sub clear_rank {
    if (&flood_protection('clearrank', 30, $slot)) { return 1; }
	my $rank = shift;
	if (!defined($rank)) { &die_nice("!clearrank was called without a rank\n"); }
	$sth = $ranks_dbh->prepare("SELECT count(*) FROM ranks WHERE rank=?");
	$sth->execute($rank) or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
	@row = $sth->fetchrow_array;
	if ($row[0]) {
	$sth = $ranks_dbh->prepare("DELETE FROM ranks WHERE rank=?");
	$sth->execute($rank) or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	&rcon_command("say " . '"Ранг"' . '"' . "^2$rank" . '"' . '"^7удален из базы данных"');
	}
	else { &rcon_command("say " . '"Ранг"' . '"' . "^2$rank" . '"' . '"^7не найден в базе данных"'); }
}

# BEGIN: !name($search_string)
sub name_player {
    if (&flood_protection('name', 30, $slot)) { return 1; }
    my $search_string = shift;
	my $slot;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	$slot = $matches[0];
	if (!defined($fake_name_by_slot{$slot})) {
    $names_sth = $names_dbh->prepare("SELECT * FROM names ORDER BY RANDOM() LIMIT 1;");
    $names_sth->execute() or &die_nice("Unable to execute query: $names_dbh->errstr\n");
	@row = $names_sth->fetchrow_array;
	if (!$row[0]) { $fake_name_by_slot{$slot} = '^2В базе данных нет имен, используйте !addname чтобы добавить имена'; }
	else { $fake_name_by_slot{$slot} = $row[1]; }
	}
	&rcon_command("say " . '"Игрока"' . "^2$name_by_slot{$slot}" . '"^7зовут"' . '"' . "^3$fake_name_by_slot{$slot}");
	}
	elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

sub database_info {
    if (&flood_protection('dbinfo', 30, $slot)) { return 1; }
    my $message = shift;
    if ($message =~ /^(bans|bans.db)$/i) {
    $sth = $bans_dbh->prepare("SELECT count(*) FROM bans");
    $sth->execute() or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2bans.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2bans.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(definitions|definitions.db)$/i) {
    $sth = $definitions_dbh->prepare("SELECT count(*) FROM definitions");
    $sth->execute() or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2definitions.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2definitions.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(guid_to_name|guid_to_name.db)$/i) {
    $sth = $guid_to_name_dbh->prepare("SELECT count(*) FROM guid_to_name");
    $sth->execute() or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2guid_to_name.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2guid_to_name.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(ip_to_guid|ip_to_guid.db)$/i) {
    $sth = $ip_to_guid_dbh->prepare("SELECT count(*) FROM ip_to_guid");
    $sth->execute() or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2ip_to_guid.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2ip_to_guid.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(ip_to_name|ip_to_name.db)$/i) {
    $sth = $ip_to_name_dbh->prepare("SELECT count(*) FROM ip_to_name");
    $sth->execute() or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2ip_to_name.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2ip_to_name.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(names|names.db)$/i) {
    $sth = $names_dbh->prepare("SELECT count(*) FROM names");
    $sth->execute() or &die_nice("Unable to execute query: $names_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2names.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2names.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(ranks|ranks.db)$/i) {
    $sth = $ranks_dbh->prepare("SELECT count(*) FROM ranks");
    $sth->execute() or &die_nice("Unable to execute query: $ranks_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2ranks.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2ranks.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(seen|seen.db)$/i) {
    $sth = $seen_dbh->prepare("SELECT count(*) FROM seen");
    $sth->execute() or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2seen.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2seen.db ^7нет записей"'); }
    }
    elsif ($message =~ /^(stats|stats.db)$/i) {
    $sth = $stats_dbh->prepare("SELECT count(*) FROM stats");
    $sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) { &rcon_command("say ^3$row[0]" . '"^7записей в базе данных ^2stats.db"'); }
    else { &rcon_command("say " . '"В базе данных ^2stats.db ^7нет записей"'); }
    }
    else {
    &rcon_command("say " . '"Неверная база данных:"' . "$message");
    sleep 1;
    &rcon_command("say " . '"Используемые базы данных: ^2bans.db^7, ^2definitions.db^7, ^2guid_to_name.db"');
    sleep 1;
    &rcon_command("say " . '"Используемые базы данных: ^2ip_to_guid.db^7, ^2ip_to_name.db^7, ^2names.db^7, ^2ranks.db"');
    sleep 1;
    &rcon_command("say " . '"Используемые базы данных: ^2seen.db^7, ^2stats.db"');
    }
}

# BEGIN: !kick($search_string)
sub kick_command {
if (&flood_protection('kick', 30, $slot)) { return 1; }
    my $search_string = shift;
    my $key;
    if ($search_string =~ /^\#(\d+)$/) {
	my $slot = $1;
	&rcon_command("say ^1$name_by_slot{$slot}" . '" ^7был выкинут админом"');
    sleep 1;
    &rcon_command("clientkick $slot");
    &log_to_file('logs/kick.log', "!KICK: $name_by_slot{$slot} was kicked by $name - GUID $guid - via the !kick command. (Search: $search_string)");
	return 0;
	}
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string"); }
    elsif ($#matches == 0) {
	&rcon_command("say ^1$name_by_slot{$matches[0]}" . '"^7был выкинут админом"');
	sleep 1;
	&rcon_command("clientkick $matches[0]");
	&log_to_file('logs/kick.log', "!KICK: $name_by_slot{$matches[0]} was kicked by $name - GUID $guid - via the !kick command. (Search: $search_string)");
	}
    elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !tempban($search_string)
sub tempban_command {
    if (&flood_protection('tempban', 30, $slot)) { return 1; }
    my $search_string = shift;
	my $tempbantime = shift;
    my $key;
    my $slot = 'undefined';
	my $minutes;
	if ($tempbantime == 1) { $minutes = '"минуту"'; }
	elsif ($tempbantime == 2 or $tempbantime == 3 or $tempbantime == 4) { $minutes = '"минуты"'; }
	else { $minutes = '"минут"'; }
    if ($search_string =~ /^\#(\d+)$/) { $slot = $1; }
	else {
	my @matches = &matching_users($search_string);
	if ($#matches == -1) {
	&rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string");
	return 0;
	}
	elsif ($#matches == 0) { $slot = $matches[0]; }
	elsif ($#matches > 0) {
	&rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string");
	return 0;
	}
	}
	my $ban_name = 'unknown';
    my $ban_ip = 'undefined';
	my $ban_guid = '12345678';
    my $unban_time = $time + $tempbantime*60;
    &rcon_command("say ^1$name_by_slot{$slot}" . '"^7был временно забанен админом на"' . "^1$tempbantime^7" . $minutes);
	if ($name_by_slot{$slot}) { $ban_name = $name_by_slot{$slot}; }
    if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) { $ban_ip = $ip_by_slot{$slot}; }
	if ($guid_by_slot{$slot}) { $ban_guid = $guid_by_slot{$slot}; }
    &log_to_file('logs/kick.log', "!TEMPBAN: $name_by_slot{$slot} was temporarily banned by $name - GUID $guid - via the !tempban command. (Search: $search_string)");  
    $bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
    $bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name) or &die_nice("Unable to do insert\n");
	&rcon_command("clientkick $slot");
}

# BEGIN: !ban($search_string)
sub ban_command {
    if (&flood_protection('ban', 30, $slot)) { return 1; }
    my $search_string = shift;
    my $key;
    my $slot = 'undefined';
    if ($search_string =~ /^\#(\d+)$/) { $slot = $1; }
	else {
    my @matches = &matching_users($search_string);
    if ($#matches == -1) {
	&rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string");
	return 0;
	}
    elsif ($#matches == 0) { $slot = $matches[0]; }
    elsif ($#matches > 0) {
	&rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string");
	return 0;
	}
	}
	my $ban_name = 'unknown';
    my $ban_ip = 'undefined';
	my $ban_guid = '12345678';
    my $unban_time = 2125091758;
    &rcon_command("say ^1$name_by_slot{$slot}" . '"^7был забанен админом"');
	if ($name_by_slot{$slot}) { $ban_name = $name_by_slot{$slot}; }
    if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) { $ban_ip = $ip_by_slot{$slot}; }
	if ($guid_by_slot{$slot}) { $ban_guid = $guid_by_slot{$slot}; }
    &log_to_file('logs/kick.log', "!BAN: $name_by_slot{$slot} was permanently banned by $name - GUID $guid - via the !ban command. (Search: $search_string)");	   
    $bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
    $bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name) or &die_nice("Unable to do insert\n");
	&rcon_command("clientkick $slot");
}

# BEGIN: !unban($target);
#  where $target = a ban ID # or a partial string match for names. 
sub unban_command {
if (&flood_protection('unban', 30, $slot)) { return 1; }
    my $unban = shift;
    my $delete_sth; 
    my $key;
    my @unban_these;
    if ($unban =~ /^\#?(\d+)$/) {
	$unban = $1;
	$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE id=?");
	}
	else {
	$unban = '%' . $unban . '%';
	$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE name LIKE ?");
	}
    $bans_sth->execute($unban) or &die_nice("Unable to do unban SELECT: $unban\n");
    while (@row = $bans_sth->fetchrow_array) {
	&rcon_command("say $row[5]" . '"^7был разбанен админом"' . "   (BAN ID#: ^1$row[0]^7" . '"удален)"');
	push (@unban_these, $row[0]);
	&log_to_file('logs/commands.log', "UNBAN: $row[5] was unbanned by an admin.   (ban id#: $row[0] deleted)");
	}
    # now clean up the database ID's.
    foreach $key (@unban_these) {
	$delete_sth = $bans_dbh->prepare("DELETE FROM bans WHERE id=?");
    $delete_sth->execute($key) or &die_nice("Unable to delete ban ID $key: unban = $unban\n");
	}
}

# BEGIN: !voting($state)
sub voting_command {
    if (&flood_protection('voting', 30, $slot)) { return 1; }
    my $state = shift;
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
	&rcon_command("g_allowVote 1");
	&rcon_command("say " . '"Голосование включено."');
	$voting = 1;
    &log_to_file('logs/admin.log', "!VOTING: voting was enabled by:  $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
    &rcon_command("g_allowVote 0");
    &rcon_command("say " . '"Голосование выключено."');
	$voting = 0;
    &log_to_file('logs/admin.log', "!VOTING: voting was disabled by:  $name - GUID $guid");
	}
	else { &rcon_command("say " . '"Неверное значение:"' . "$state" . '"... Используйте: on или off"'); }
}

# BEGIN: !voice($state)
sub voice_command {
    if (&flood_protection('voice', 30, $slot)) { return 1; }
    my $voice;
    my $state = shift;
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
	&rcon_command("sv_voice 1");
	&rcon_command("say " . '"Голосовой чат включен."');
	$voice = 1;
    &log_to_file('logs/admin.log', "!voice: voice chat was enabled by:  $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
    &rcon_command("sv_voice 0");
    &rcon_command("say " . '"Голосовой чат выключен."');
	$voice = 0;
    &log_to_file('logs/admin.log', "!voice: voice chat was disabled by:  $name - GUID $guid");
	}
	else { &rcon_command("say " . '"Неверное значение:"' . "$state" . '"... Используйте: on или off"'); }
}

# BEGIN: !killcam($state)
sub killcam_command {
    if (&flood_protection('killcam', 30, $slot)) { return 1; }
    my $state = shift;
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
    &rcon_command("scr_killcam 1");
    &rcon_command("say " . '"Показ гибели был ВКЛЮЧЕН админом"');
    &log_to_file('logs/admin.log', "!KILLCAM: the kill-cam was enabled by:  $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
    &rcon_command("scr_killcam 0");
    &rcon_command("say " . '"Показ гибели был ВЫКЛЮЧЕН админом"');
    &log_to_file('logs/admin.log', "!KILLCAM: the kill-cam was disabled by:  $name - GUID $guid");
	}
	else { &rcon_command("say " . '"Неизвстное значение команды !killcam:"' . "  $state  " . '" Используйте: on или off"'); }
}

# BEGIN: !speed($speed)
sub speed_command {
    my $speed = shift;
    if ($speed =~ /^\d+$/) {
    &rcon_command("g_speed $speed");
    &rcon_command("say " . '"Скорость установлена на значение:"' . "^2$speed");
    &log_to_file('logs/admin.log', "!speed: speed was set to $speed by:  $name - GUID $guid");
	}
	else {
    my $query = &rcon_query("g_speed");
    if ($query =~ /\"g_speed\" is: \"(\d+)\^7\"/m) {
    $speed = $1;
    &rcon_command("say " . '"Значение скорости сейчас установлено на:"' . "^2$speed");
	}
    else { &rcon_command("say " . '"К сожалению, не удалось установить значение скорости"'); }
	}
}

# BEGIN: !gravity($gravity)
sub gravity_command {
    my $gravity = shift;
    if ($gravity =~ /^\d+$/) {
    &rcon_command("g_gravity $gravity");
    &rcon_command("say " . '"Гравитация установлена на значение:"' . "^1$gravity");
    &log_to_file('logs/admin.log', "!gravity: gravity was set to $gravity by:  $name - GUID $guid");
	}
	else {
    my $query = &rcon_query("g_gravity");
    if ($query =~ /\"g_gravity\" is: \"(\d+)\^7\"/m) {
    $gravity = $1;
    &rcon_command("say " . '"^7Значение гравитации сейчас установлено на:"' . "^1$gravity");
	}
    else { &rcon_command("say " . '"К сожалению, не удалось установить значение гравитации"'); }
	}
}

# BEGIN: !glitch($state)
sub glitch_command {
    if (&flood_protection('glitch', 30, $slot)) { return 1; }
    my $state = shift;
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
	$config->{'glitch_server_mode'} = 1;
    &rcon_command("say " . '"Дружелюбный режим включен. ^1УБИВАТЬ ТЕПЕРЬ ЗАПРЕЩЕНО!"');
    &log_to_file('logs/admin.log', "!GLITCH: glitch mode was enabled by:  $name - GUID $guid");
	}
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
	$config->{'glitch_server_mode'} = 0;
    &rcon_command("say " . '"Дружелюбный режим выключен. ^2УБИВАТЬ ТЕПЕРЬ РАЗРЕШЕНО!"');
    &log_to_file('logs/admin.log', "!GLITCH: glitch mode was disabled by:  $name - GUID $guid");
	}
	else { &rcon_command("say " . '"Неизвестное значение команды glitch:"' . "$state" . '" Используйте: on или off"'); }
}

# BEGIN: !best
sub best {
    if (&flood_protection('best', 300)) { return 1; }
    my $counter = 1;
    &rcon_command("say " . '"^2Лучшие ^7игроки сервера:"');
    sleep 1;
    # Most Kills
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and kills > 0 ORDER BY kills DESC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^2Наибольшее количество убийств^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
	&rcon_command("say ^3" . ($counter++) . '"^7место:"' . "^2$row[1]" . '"^7с^2"' . "$row[2]" . '"^7убийствами"');
	sleep 1;
    }
    # Best Kill to Death ratio
    $counter = 1;
    sleep 1;
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and kills > 100 ORDER BY (kills * 10000 / deaths) DESC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^2Игроки с лучшим к/д соотношением^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
    &rcon_command("say ^3" . ($counter++) . '"^7место:"' . "^2$row[1]" . '"^7с^8"' . ( int($row[2] / $row[3] * 100) / 100 ) . '"^7к/д соотношением"');
    sleep 1;
    }
    # Best Headshot Percentages
    $counter = 1;
    sleep 1;
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and kills > 100 ORDER BY (headshots * 10000 / kills) DESC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^2Лучший процент хедшотов^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command("say ^3" . ($counter++) . '"^7место:"' . "^2$row[1]" . '"^7с^3"' . ( int($row[4] / $row[2] * 10000) / 100 ) . '"^7процентами хедшотов"');
        sleep 1;
   }
    # Best Kill Spree
    $counter = 1;
    sleep 1;
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and best_killspree > 0 ORDER BY best_killspree DESC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^2Лучшие серии убийств^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command("say ^3" . ($counter++) . '"^7место:"' . "^2$row[1]" . '"^7с^6"' .  "$row[12]" . '"^7убийствами подряд"');
        sleep 1;
    }
	if ($game_type eq 'sd') {
	# Best Bomb Plants
    $counter = 1;
    sleep 1;
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and bomb_plants > 0 ORDER BY bomb_plants DESC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^2Наибольшее количество заложенной взрывчатки^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command("say ^3" . ($counter++) . '"^7место:"' . "^2$row[1]" . '"^7с^4"' .  "$row[16]" . '"^7закладками взрывчатки"');
        sleep 1;
    }
	# Best Bomb Defuses
    $counter = 1;
    sleep 1;
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and bomb_defuses > 0 ORDER BY bomb_defuses DESC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^2Наибольшее количество обезвреженной взрывчатки^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command("say ^3" . ($counter++) . '"^7место:"' . "^2$row[1]" . '"^7с^5"' .  "$row[17]" . '"^7обезвреживаниями взрывчатки"');
        sleep 1;
    }
	}
}

sub change_gametype {
    my $gametype = shift;
    if (!defined($gametype)) {
	print "WARNING: change_gametype was called without a game type\n";
	return;
	}
    if ($gametype !~ /^(dm|tdm|ctf|hq|sd)$/) {
	print "WARNING: change_gametype was called with an invalid game_type: $gametype\n";
    return;
	}
    if (&flood_protection('gametype', 30, $slot)) { return 1; }
    &rcon_command("say " . '"^2Смена режима игры на^7:^3"' . ($description{$gametype}));
    &rcon_command("g_gametype $gametype");
    sleep 1;
    &rcon_command("map_restart");
    &log_to_file('logs/commands.log', "$name change the game type to: $gametype");
}

# BEGIN: check_player_names
sub check_player_names {
    print "Checking for bad names...\n"; 
    my $match_string;
    my $warned;
    foreach $slot (sort { $a <=> $b } keys %name_by_slot) {
	$warned = 0;
        if ($slot >= 0) {
	    foreach $match_string (@banned_names) {
		if ($name_by_slot{$slot} =~ /$match_string/) {
		    $warned = 1;
		    if (!defined($name_warn_level{$slot})) { $name_warn_level{$slot} = 0; }
		    if ($name_warn_level{$slot} == 0) {
			print "NAME_WARN1: $name_by_slot{$slot} is using a banned name.  Match: $match_string\n";
			&rcon_command("tell $slot ^1$name_by_slot{$slot}^7:" . '"' . $config->{'banned_name_warn_message_1'} );
			$name_warn_level{$slot} = 1;
		    }
			elsif ($name_warn_level{$slot} == 1) {
			print "NAME_WARN2: $name_by_slot{$slot} is using a banned name.  (2nd warning) Match: $match_string\n";
            &rcon_command("tell $slot ^1$name_by_slot{$slot}^7:" . '"' . $config->{'banned_name_warn_message_2'} );
            $name_warn_level{$slot} = 2;
            }
			elsif ($name_warn_level{$slot} == 2) {
            print "NAME_KICK: $name_by_slot{$slot} is using a banned name.  (3rd strike) Match: $match_string\n";
            &rcon_command("tell $slot ^1$name_by_slot{$slot}^7:" . '"' . $config->{'banned_name_kick_message'} );
            sleep 1;
			&rcon_command("clientkick $slot");
			&log_to_file('logs/kick.log', "BANNED NAME: $name_by_slot{$slot} was kicked for having a banned name:  Match: $match_string");
		    }
		}
	    }
	}
	if ((!defined($name_warn_level{$slot})) or (!$warned)) { $name_warn_level{$slot} = 0; }
    }
}
# END: check_player_names

# BEGIN: make_announcement
sub make_announcement {
    my $total = $#announcements;
    my $announce = $announcements[int(rand($total))];
    print "Making Announcement: $announce\n";
    &rcon_command("say $announce");
}
# END: make_announcement

# BEGIN: !names(search_string);
sub names {
    my $search_string = shift;
    my $key;
    my @matches = &matching_users($search_string);
    my @names;
    my $ip;
    my $guessed = 0;
    if ($#matches == -1) {
	if (&flood_protection('names-nomatch', 15, $slot)) { return 1; }
	&rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string");
    }
    elsif ($#matches == 0) {
        &log_to_file('logs/commands.log', "$name executed an !names search for $name_by_slot{$matches[0]}");
        if ($guid_by_slot{$matches[0]} > 0) {
            $sth = $guid_to_name_dbh->prepare("SELECT name FROM guid_to_name WHERE guid=? ORDER BY id DESC LIMIT 10;");
            $sth->execute($guid_by_slot{$matches[0]}) or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
            while (@row = $sth->fetchrow_array) { push @names, $row[0]; }
        }
	$ip = $ip_by_slot{$matches[0]};
	if ($ip =~ /\?$/) {
	    $ip =~ s/\?$//;
	    $guessed = 1;
	}
        if ($ip =~ /\d+\.\d+\.\d+\.\d+/) {
            $sth = $ip_to_name_dbh->prepare("SELECT name FROM ip_to_name WHERE ip=? ORDER BY id DESC LIMIT 10;");
            $sth->execute($ip) or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
            while (@row = $sth->fetchrow_array) { push @names, $row[0]; }
        }
        if ($#names == -1) {
	    if (&flood_protection('names-none', 15, $slot)) { return 1; }
	    &rcon_command("say " . '"Не найдено имен для:"' . " $name_by_slot{$matches[0]}");
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
                    #  1) it is a name that has more colors than what is already in the list
                    if (defined($name_hash{&strip_color($name)})) {
                        # This is a more colorful version of something already in the list.
                        # Toast the old name.
                        delete $name_hash{&strip_color($name)};
                        # Add the new one
                        $name_hash{$name} = 1;
                    }
                    #  2) It is not present in any form in the list.
                    # (or may be a less colorful version of what is already in the list.
                    else { $name_hash{$name} = 1; }
                    # 3) it is a name that has less colors than what is already in the list
                    foreach $key (keys %name_hash) {
                        if (($name ne $key) && ($name eq &strip_color($key))) {
                            # Then we know that the name is a less colorful version of what is already in the list.
                            delete $name_hash{$name};
                            last;
                        }
                    }
                }
            }
            # finally, announce the list.
	    my $found_none = 1;
	    my @announce_list = keys %name_hash;
	    if (&flood_protection('names', (15 + (5 * $#announce_list)), $slot)) { return 1; }
            foreach $key (@announce_list) {
                if ($name_by_slot{$matches[0]} ne $key) {
		    if ($guessed) { &rcon_command("say $name_by_slot{$matches[0]}" . '" ^7вероятно еще играл как:"' . '"' . " $key"); }
		    else { &rcon_command("say $name_by_slot{$matches[0]}" . '" ^7еще играл как:"' . '"' . " $key"); }
		    $found_none = 0;
                }
            }
	    if ($found_none) { &rcon_command("say " . '"Не найдено имен для"' ." $name_by_slot{$matches[0]}"); }
        }
    }
    elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много совпадений с: "' . '"' . "$search_string"); }
}

# BEGIN: !worst
sub worst {
    if (&flood_protection('worst', 300)) { return 1; }
    &rcon_command("say " . '"^1Худшие ^7игроки сервера:"');
    my $counter = 1;
    sleep 1;
    # Most deaths
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and deaths > 0 ORDER BY deaths DESC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say" . '"^1Наибольшее количество смертей^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command("say ^3" . ($counter++) . "^7" . '"место:^1"' . "$row[1]" . '"^7с^1"' . "$row[3]" . '"^7смертями"');
        sleep 1;
    }
    # Worst k2d ratio
    $counter = 1;
    sleep 1;
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and ((kills > 100) and (deaths > 50)) ORDER BY (kills * 10000 / deaths) ASC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^1Игроки с худшим к/д соотношением^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command("say ^3" . ($counter++) . "^7" . '"место:^1"' . "$row[1]" . '"^7с^8"' . ( int($row[2] / $row[3] * 100) / 100 ) . '"^7к/д соотношением"');
        sleep 1;
    }
    # Worst headshot percentages
    $counter = 1;
    sleep 1;
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" and name != "UnnamedPlayer" and ((kills > 100) and (headshots > 10)) ORDER BY (headshots * 10000 / kills) ASC LIMIT 5;');
    $sth->execute or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command("say " . '"^1Худший процент хедшотов^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command("say ^3" . ($counter++) . "^7" . '"место:^1"' .  "$row[1]" . '"^7c^3"' . ( int($row[4] / $row[2] * 10000) / 100 ) . '"^7процентами хедшотов"');
        sleep 1;
    }
}

# BEGIN:  &guid_sanity_check($guid,$ip);
sub guid_sanity_check {
    my $should_be_guid = shift;
    my $ip = shift;
    $last_guid_sanity_check = $time;
    # make sure that the GUID sanity check is enabled before proceeding.
    if ($config->{'guid_sanity_check'}) {}
    else { return 0; }
    print "Running GUID sanity check\n";
    # check to make sure that IP -> GUID = last guid
    print "Look Up GUID for $ip and make sure it is $should_be_guid\n";
    # if guid is nonzero and is not last_guid, then we know sanity fails.
    my $total_tries = 3; # The total number of attempts to get an answer out of activision.
    my $read_timeout = 1; # Number of seconds to wait for activison to respond to a packet.
    my $activision_master = 'cod2master.activision.com';
    my $port = 20700;
    my $ip_address = $ip;
    my $d_ip;
    my $message;
    my $current_try = 0;
    my $still_waiting = 1;
    my $got_response = 0;
    my $maximum_lenth = 200;
    my $portaddr;
    my ($session_id, $result, $reason, $guid);
    print "\nAsking $activision_master if $ip_address has provided a valid key recently.\n\n";
    socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp")) or &die_nice("Socket error: $!");
    my $random = int(rand(7654321));
    my $send_message = "\xFF\xFF\xFF\xFFgetIpAuthorize $random $ip_address  0";
    $d_ip = gethostbyname($activision_master);
    my $selecta = IO::Select->new;
    $selecta->add(\*SOCKET);
    my @ready;
    while (($current_try++ < $total_tries) && ($still_waiting)) {
    # Send the packet
	$portaddr = sockaddr_in($port, $d_ip);
	send(SOCKET, $send_message, 0, $portaddr) == length($send_message) or &die_nice("Cannot send to $ip_address($port): $!\n\n");
	# Check to see if there is a response yet.
	@ready = $selecta->can_read($read_timeout);
	if (defined($ready[0])) {
	    # Yes, the socket is ready.
	    $portaddr = recv(SOCKET, $message, $maximum_lenth, 0) or &die_nice("Socket error: recv: $!");
	    # strip the 4 \xFF bytes at the begining.
	    $message =~ s/^.{4}//;
	    $got_response = 1;
	    $still_waiting = 0;
	}
    }
    if ($got_response) {
	if ($message =~ /ipAuthorize ([\d\-]+) ([a-z]+) (\w+) (\d+)/) {
	    ($session_id, $result, $reason, $guid) = ($1,$2,$3,$4);
	    print "RESULTS:\n";
	    print "\tIP Address: $ip_address\n";
	    print "\tAction: $result\n";
	    print "\tReason: $reason\n";
	    print "\tGUID: $guid\n";
	    print "\n";
	    if ($reason eq 'CLIENT_UNKNOWN_TO_AUTH') {
		print "Explaination of: $reason\n";
		print "\tThis IP Address has not provided any CD Keys to the activision server\n";
		print "\tThis IP Address may not playing COD2 currently, or\n";
		print "\tActivision has not heard a key from this IP recently.\n";
	    }
	    if ($reason eq 'BANNED_CDKEY') {
		print "Explaination of: $reason\n";
		print "\tThis IP Address is using a well known stolen CD Key.\n";
		print "\tActivision has BANNED this CD Key and will not allow anyone to use it.\n";
		print "\tThis IP address is using a stolen copy of CoD2\n\n";
	    }
	    if ($reason eq 'INVALID_CDKEY') {
		print "Explaination of: $reason\n";
		print "\tThis IP Address is trying to use the same CD Key from multiple IPs.\n";
		print "\tActivision has already seen this Key recently used by a different IP.\n";
		print "\tThis is a valid CD Key, but is being used from multiple locations\n";
		print "\tActivision only allows one IP per key.\n\n";
	    }
        # Now, check to make sure our GUID numbers match up.
	    if ($guid) {
		if ($guid eq $should_be_guid) { print "\nOK: GUID Sanity check: PASSED\n\n"; }
		else {
		    &rcon_command("say " . '"^1ПРЕДУПРЕЖДЕНИЕ: ^7Проверка корректности GUID не пройдена для"' . "$name_by_slot{$most_recent_slot}");
		    print "\nFAIL: GUID Sanity check: FAILED\n";
		    print "    IP: $ip was supposed to be GUID $should_be_guid but came back as $guid\n\n";
		    &log_to_file('logs/guid.log', "SANITY FAILED: $name_by_slot{$most_recent_slot}  IP: $ip was supposed to be GUID $should_be_guid but came back as $guid - Server has been up for: $uptime");
		}
	    }
	}
	else {
	    print "\nERROR:\n\tGot a response, but not in the format expected\n";
	    print "\t$message\n\n";
	}
    }
	else {
	print "\nERROR:\n\t$activision_master is not currently responding to requests.\n";
	print "\n\tSorry.  Try again later.\n\n";
    }
    $most_recent_guid = 0;
    $most_recent_slot = 0;
}
# END: &guid_sanity_check

# BEGIN: &flood_protection($attribute,$interval,$slot)
sub flood_protection {
    my $attribute = shift;
    my $min_interval = shift;
    my $slot = shift;
    # Make sure that flood protection is enabled. Otherwise, all is allowed.
    if ($config->{'flood_protection'}) { }
    else { return 0; }
    # Exemption for global admins (3 seconds delay)
    if (&check_access('flood_exemption')) { $min_interval = 3; }
    # Ensure that all values are defined.
    if ((!defined($min_interval)) or ($min_interval !~ /^\d+$/)) { $min_interval = 30; }
    if ((!defined($slot)) or ($slot !~ /^\d+$/)) { $slot = 'global'; }
    my $key = $attribute . '.' . $slot;
    if (!defined($flood_protect{$key})) { $flood_protect{$key} = 0; }
    if ($time >= $flood_protect{$key}) {
	# The command is allowed
	$flood_protect{$key} = $time + $min_interval;
	return 0;
    }
	else {
	# Too soon,  flood protection triggured.
	print "Flood protection activated.  '$attribute' command not allowed to be run again yet.\n";
	print "\tNot allowed to run for another  " . &duration(($flood_protect{$key} - $time)) . "\n";
	&log_to_file('logs/flood_protect.log', "Denied command access to $name for $attribute.  Not allowed to run for another  " . &duration(($flood_protect{$key} - $time)));
	return 1;
    }
}
# END: &flood_protection

# BEGIN: &tell($search_string,$message);
sub tell {
    my $search_string = shift;
    my $message = shift;
    my $key;
    if ((!defined($search_string)) or ($search_string !~ /./)) { return 1; }
    if ((!defined($message)) or ($message !~ /./)) { return 1; }
    my @matches = &matching_users($search_string);
    if ($#matches == -1) {
        if (&flood_protection('tell-nomatch', 15, $slot)) { return 1; }
        &rcon_command("say " . '"Нет совпадений с: "' . '"' . "$search_string");
    }
    else {
	if (&flood_protection('tell', 30, $slot)) { return 1; }
	foreach $key (@matches) { &rcon_command("say ^2" . "$name_by_slot{$key}" . "^7: " . '"' . "$message"); }
    }
}
# END: &tell($search_string,$message);

# BEGIN: &last_bans($number);
sub last_bans {
    my $number = shift;
    # keep some sane limits.
    if ($number > 10) { $number = 10; }
    if ($number < 0) { $number = 1; }
    $number = int($number);
    if (&flood_protection('lastbans', 30, $slot)) { return 1; }
    $bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE unban_time > $time ORDER BY id DESC LIMIT $number");
    $bans_sth->execute or &die_nice("Unable to do select recent bans\n");
    while (@row = $bans_sth->fetchrow_array) {
	my $txt_time = &duration($time - $row[1]);
    &rcon_command("say ^2$row[5]" . '"^7был забанен"' . "$txt_time" . '"назад"' . "(BAN ID#: ^1$row[0]^7, IP - ^3$row[3]^7, GUID - ^3$row[4]^7)");
    sleep 1;
	}
	if (!$row[0]) { &rcon_command("say " . '"В последнее время не было забаненных игроков."'); }
}
# END: &last_bans($number);

sub dictionary {
    my $word = shift;
    my @lines;
    my @definitions;
    my $definition;
    my $term;
    my $content;
    my $counter = 0;

    if (!defined($word)) {
	&rcon_command("say " . '"!define что?"');
	return 1;
    }
    # If we are being asked to define a word, define it and return
    if ($word =~ /(.*)\s+=\s+(.*)/) {
	($term,$definition) = ($1,$2);
	$term =~ s/\s*$//;
	if (&check_access('define')) {
	    $sth = $definitions_dbh->prepare("INSERT INTO definitions VALUES (NULL, ?, ?)");
	    $sth->execute($term,$definition) or &die_nice("Unable to do insert\n");
	    &rcon_command("say " . '" ^2Добавлено определение для: "' . '"' . "^1$term");
	    return 0;
	}
    }
    # Now, Most imporant are the definitions that have been manually defined.
    # They come first.
    $sth = $definitions_dbh->prepare('SELECT definition FROM definitions WHERE term=?;');
    $sth->execute($word) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
    while (@row = $sth->fetchrow_array) {
        print "DATABASE DEFINITION: $row[0]\n";
        $counter++;
	if ($#definitions < 8) { push (@definitions, "^$counter$counter^7) ^2 $row[0]"); }
    }
    # Now we sanatize what we're looking for - online databases don't have multiword definitions.
    if ($word =~ /[^A-Za-z\-\_\s\d]/) {
	&rcon_command("say " . '"Неверный ввод, используйте !define = *слово* чтобы добавить его в базу данных"');
	sleep 1;
	&rcon_command("say " . '"Или !define *слово* чтобы посмотреть результаты из онлайн-словаря WordNet"');
    return 1;
    }
    $sth = $definitions_dbh->prepare('SELECT count(id) FROM cached WHERE term=?;');
    $sth->execute($word) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
    @row = $sth->fetchrow_array;
    if ($row[0]) {
	# skip the lookup - we have it cached - intead, we pull the data from our database cache.
	$sth = $definitions_dbh->prepare('SELECT definition FROM cached_definitions WHERE term=?;');
	$sth->execute($word) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
	while (@row = $sth->fetchrow_array) {
	    print "CACHED ONLINE DEFINITION: $row[0]\n";
	    $counter++;
	    if ($#definitions < 8) { push (@definitions, "^$counter$counter^7) ^2 $row[0]"); }
	}
    }
	else {
	$content = get("http://wordnetweb.princeton.edu/perl/webwn?s=" . $word);
	if (!defined($content)) {
	    &rcon_command("say " . '"Словарь WordNet в настоящее время недоступен, попробуйте позже"');
	    return 1;
	}
	@lines = split(/\n+/,$content);
	foreach (@lines) {
	    if (/<\s*b>$word<\/b>[^\(]+\(([^\)]*)\)/) {
		$definition = $1;
		$counter++;
		$sth = $definitions_dbh->prepare("INSERT INTO cached_definitions VALUES (NULL, ?, ?)");
		$sth->execute($word,$definition) or &die_nice("Unable to do insert\n");
		# 8 definitions max by default
		if ($#definitions < 8) { push (@definitions, "^$counter$counter^7) ^2 $definition"); }
	    }
	}
	$sth = $definitions_dbh->prepare("INSERT INTO cached VALUES (NULL, ?)");
	$sth->execute($word) or &die_nice("Unable to do insert into dictionary - cached table\n");
    }
    if (!$counter) { &rcon_command("say " . '"^7К сожалению, не найдено определений для слова:"' . "^2$word"); }
	else {
    if ($counter == 1) { &rcon_command("say " . '"^21 ^7определение найдено для слова:"' . "^2$word"); }
	else { &rcon_command("say ^2$counter " . '"^7определений найдено для слова:"' . "^2$word"); }
	sleep 1;
        foreach $definition (@definitions) {
        &rcon_command("say $definition");
	    sleep 1;
        }
    }
}

sub check_guid_zero_players {
    my $slot;
    my @possible;
    my $start_time = $time;
    my $max_time = 10;
    print "GUID ZERO audit in progress...\n\n";
    foreach $slot (keys %guid_by_slot) {
	if ((defined($guid_by_slot{$slot})) && (defined($ip_by_slot{$slot})) && ($guid_by_slot{$slot} == 0) && ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) { push @possible, $slot; }
    }
    if ($#possible == -1) {
	print "GUID Zero Audit: PASSED, there are no GUID zero players.\n";
	return 1;
    }
    &fisher_yates_shuffle(\@possible);
    my $total_tries = 3; # The total number of attempts to get an answer out of activision.
    my $read_timeout = 1; # Number of seconds to wait for activison to respond to a packet.
    my $activision_master = 'cod2master.activision.com';
    my $port = 20700;
    my $ip_address;
    my $d_ip = gethostbyname($activision_master);
    my $message;
    my $current_try = 0;
    my $still_waiting = 1;
    my $got_response = 0;
    my $maximum_lenth = 200;
    my $portaddr;
    my ($session_id, $result, $reason, $guid);
    my $random;
    my $send_message;
    my $selecta;
    my @ready;
    my $kick_reason;
    my $dirtbag;
    # Try as many as we can within our time limit
    foreach $slot (@possible) {
	$current_try = 0;
	$still_waiting = 1;
	$got_response = 0;
	$random = int(rand(7654321));
	$send_message = "\xFF\xFF\xFF\xFFgetIpAuthorize $random $ip_by_slot{$slot}  0";
	print "AUDITING: slot: $slot  ip: " . $ip_by_slot{$slot} . "  guid: " . $guid_by_slot{$slot} . "  name: " . $name_by_slot{$slot} . "\n";
	print "\nAsking $activision_master if $ip_by_slot{$slot} has provided a valid key recently.\n\n";
	socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp")) or &die_nice("Socket error: $!");
	$selecta = IO::Select->new;
	$selecta->add(\*SOCKET);
	while (($current_try++ < $total_tries) && ($still_waiting)) {
	    # Send the packet
	    $portaddr = sockaddr_in($port, $d_ip);
	    send(SOCKET, $send_message, 0, $portaddr) == length($send_message) or &die_nice("cannot send to $ip_address($port): $!\n\n");
	    # Check to see if there is a response yet.
	    @ready = $selecta->can_read($read_timeout);
	    if (defined($ready[0])) {
		# Yes, the socket is ready.
		$portaddr = recv(SOCKET, $message, $maximum_lenth, 0) or &die_nice("Socket error: recv: $!");
		# strip the 4 \xFF bytes at the begining.
		$message =~ s/^.{4}//;
		$got_response = 1;
		$still_waiting = 0;
	    }
	}
	if ($got_response) {
	    if ($message =~ /ipAuthorize ([\d\-]+) ([a-z]+) (\w+) (\d+)/) {
		($session_id, $result, $reason, $guid) = ($1,$2,$3,$4);
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
		    print "\t  Activision has not heard a key from this IP recently.\n";
		}
		if ($reason eq 'BANNED_CDKEY') {
		    print "Explaination of: $reason\n";
		    print "\tThis IP Address is using a well known stolen CD Key.\n";
		    print "\tActivision has BANNED this CD Key and will not allow anyone to use it.\n";
		    print "\tThis IP address is using a stolen copy of CoD2\n\n";
		    $dirtbag = 1;
		    $kick_reason = "using a STOLEN CD-Key that Activision has BANNED.  ^1Go buy the game.";
		}
		if ($reason eq 'INVALID_CDKEY') {
		    print "Explaination of: $reason\n";
		    print "\tThis IP Address is trying to use the same CD Key from multiple IPs.\n";
		    print "\tActivision has already seen this Key recently used by a different IP.\n";
		    print "\tThis is a valid CD Key, but is being used from multiple locations\n";
		    print "\tActivision only allows one IP per key.\n\n";
		    $dirtbag = 1;
		    $kick_reason = "an ^4invalid CD-KEY^2.  Perhaps your CD-KEY is already in use?";
		}
		if (($dirtbag) && ($reason eq 'BANNED_CDKEY')) {
		    print"DIRTBAG: $name_by_slot{$slot} - $reason\n";
		    &rcon_command("say ^1$name_by_slot{$slot} ^2was kicked for $kick_reason");
		    sleep 1;
		    &rcon_command("clientkick $slot");
		    &log_to_file('logs/kick.log', "CD-KEY: $name_by_slot{$slot} was kicked for: $kick_reason");
			my $ban_name = 'unknown';
		    my $ban_ip = 'undefined';
			my $ban_guid = '12345678';
		    my $unban_time = $time + 28800;
			if ($name_by_slot{$slot}) { $ban_name = $name_by_slot{$slot}; }
		    if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) { $ban_ip = $ip_by_slot{$slot}; }
			if ($guid_by_slot{$slot}) { $ban_guid = $guid_by_slot{$slot}; }
		    $bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
		    $bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name) or &die_nice("Unable to do insert\n");
		}
	    }
	}
	# abort the rest if we are out of time.
	if ((time - $start_time) > $max_time) { last; }
    }
}

sub fisher_yates_shuffle {
    my $array = shift;
    my $i;
    for ($i = @$array; --$i; ) {
        my $j = int rand ($i+1);
        next if $i == $j;
        @$array[$i,$j] = @$array[$j,$i];
    }
}

sub tan {
 sin($_[0]) / cos($_[0])
}

sub random_pwd {
    my $length = shift;
    my @chars = (0 .. 9, 'a' .. 'z', 'A' .. 'Z');
    return join '', @chars[ map rand @chars, 0 .. $length ];
}

 sub ftp_connect {
    # initialize FTP connection here.
    fileparse_set_fstype; # FTP uses UNIX rules
    $ftp_tmpFileName = tmpnam;
    $ftp_verbose && warn "FTP $ftp_host\n";
    $ftp=Net::FTP->new($ftp_host,Timeout=>60) or &die_nice("FTP: Cannot ftp to $ftp_host: $!", $ftpfail = 1);
    $ftp_verbose && warn "USER: " . $config->{'ftp_username'} . " \t PASSWORD: ". '*'x length($config->{'ftp_password'}). "\n"; # hide password
    $ftp->login($config->{'ftp_username'},$config->{'ftp_password'}) or &die_nice("FTP: Can't login to $ftp_host: $!", $ftpfail = 1);
    $ftp_verbose && warn "CWD: $ftp_dirname\n";
    $ftp->cwd($ftp_dirname) or &die_nice("FTP: Can't cd  $!", $ftpfail = 1);
    if ($config->{'use_passive_ftp'}) {
	print "Using Passive ftp mode...\n\n";
	$ftp->pasv or &die_nice($ftp->message);
	}
    $ftp_lines && &ftp_getNlines;
    $ftp_type = $ftp->binary;
    $ftp_lastEnd = $ftp->size($ftp_basename) or &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n");
    $ftp_verbose && warn "SIZE $ftp_basename: " . $ftp_lastEnd . " bytes\n\n";
}

sub ftp_getNlines {
    my $bytes = ($ftp_lines+1) * 120; # guess how many bytes we have to download to get N lines
    my $keepGoing;
    my @data;
    my $length;
    do {
        my $actualBytes = &ftp_getNchars($bytes);
        open(FILE,$ftp_tmpFileName) or &die_nice("FTP: Could not open $ftp_tmpFileName");
        @data = <FILE>;
        close(FILE);
        unlink($ftp_tmpFileName);
        $length = $#data;
        $keepGoing = ($length<=$ftp_lines && $actualBytes==$bytes); #we want to download one extra line (to avoid truncation)
        $bytes = $bytes * 2; # get more bytes this time. TODO: could calculate average line length and use that
    }
	while ($keepGoing);
    $ftp_inbandSignaling && print "#START: (This is a hack to signal start of data in pipe)\n";
    # just print the last N lines
    my $startLine = $length-$ftp_lines;
    if ($startLine<0) { $startLine=0; }
    for (my $i=$startLine+1; $i<=$length; $i++) { push @ftp_buffer, $data[$i]; }
    @ftp_buffer = reverse @ftp_buffer;
    $ftp_inbandSignaling && print "#END: (This is a hack to signal end of data in pipe)\n";
    $ftp_inbandSignaling && &ftp_flushPipe;
}

# pipe size (512 bytes, -p) 8
sub ftp_flushPipe {
    print " "x(512*8);
    print "\n";
}

# get N bytes and store in tempfile, return number of bytes downloaded
sub ftp_getNchars {
    my ($bytes) = @_;
    my $type = $ftp->binary;
    my $size = $ftp->size($ftp_basename) or &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n", $ftpfail = 1);
    my $startPos = $size - $bytes;
    if ($startPos<0) { $startPos=0; $bytes=$size; } #file is smaller than requested number of bytes
    -e $ftp_tmpFileName && &die_nice("FTP: $ftp_tmpFileName exists");
    $ftp_verbose && warn "GET: $ftp_basename, $ftp_tmpFileName, $startPos\n";
    $ftp->get($ftp_basename,$ftp_tmpFileName,$startPos);
    return $bytes;
}

sub ftp_get_line {
    my $line;
    if (!defined($ftp_buffer[0])) {
	$ftp_type = $ftp->binary;
        $ftp_currentEnd = $ftp->size($ftp_basename) or &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n", $ftpfail = 1);
        if ($ftp_currentEnd > $ftp_lastEnd) {
            $ftp_verbose && warn "FTP: SIZE $ftp_basename increased: ".($ftp_currentEnd-$ftp_lastEnd)." bytes\n";
            $ftp_verbose && warn "FTP: GET: $ftp_basename, $ftp_tmpFileName, $ftp_lastEnd\n";
            -e $ftp_tmpFileName && &die_nice("FTP: $ftp_tmpFileName exists");
	    while (!-e $ftp_tmpFileName) { $ftp->get($ftp_basename,$ftp_tmpFileName,$ftp_lastEnd); }
            open(FILE,$ftp_tmpFileName) or &die_nice("FTP: Could not open $ftp_tmpFileName");
            $ftp_inbandSignaling && print "#START: (This is a hack to signal start of data in pipe)\n";
	    while ($line = <FILE>) { push @ftp_buffer, $line; }
            close(FILE);
            $ftp_inbandSignaling && print "#END: (This is a hack to signal end of data in pipe)\n";
            $ftp_inbandSignaling && &ftp_flushPipe;
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

# &toggle_weapon('scr_allow_smokegrenades', 'Smoke Grenades', $2);
sub toggle_weapon {
    my ($attribute, $description, $requested_state) = (@_);
    my $is_was;
    if ($description =~ /s$/i) { $is_was = 'were'; }
    else { $is_was = 'was'; }
    if ($requested_state =~ /yes|1|on|enable/i) {
	&log_to_file('logs/admin.log', "$description $is_was enabled by:  $name - GUID $guid");
	&rcon_command("set $attribute \"1\"");
	&rcon_command("say " . "^2$description" .  '"^7были ^2ВКЛЮЧЕНЫ^7 админом."');
    }
	elsif ($requested_state =~ /no|0|off|disable/i) {
        &log_to_file('logs/admin.log', "$description $is_was disabled by:  $name - GUID $guid");
        &rcon_command("set $attribute \"0\"");
        &rcon_command("say " . "^2$description" .  '"^7были ^1ВЫКЛЮЧЕНЫ^7 админом."');
    }
	else {
	&log_to_file('logs/admin.log', "$description $is_was set to $requested_state:  $name - GUID $guid");
        &rcon_command("set $attribute \"$requested_state\"");
        &rcon_command("say " . "^2$description" . '"^7были установлены в режим"' . "^1$requested_state" . '"^7админом."');
    }
}

sub update_name_by_slot {
    my $name = shift;
    my $slot = shift;
    if ((!defined($slot)) or ($slot !~ /^\-?\d+$/)) { &die_nice("invalid slot number passed to update_slot_by_name: $slot\n\n"); }
    if (!defined($name)) { &die_nice("invalid name passed to update_slot_by_name: $name\n\n"); }
    if ($slot == -1) { return; }
    # strip trailing spaces from the name.
    $name =~ s/\s+$//;
    if (!defined($name_by_slot{$slot})) { $name_by_slot{$slot} = $name; }
    elsif ($name_by_slot{$slot} ne $name) {
	if (($name_by_slot{$slot} ne 'SLOT_EMPTY') && ($name ne 'SLOT_EMPTY')) {
	    if (($name_by_slot{$slot} ne &strip_color($name)) && ((&strip_color($name_by_slot{$slot}) ne $name))) {
		print "NAME CHANGE: $name_by_slot{$slot} changed their name to: $name\n";
		# Detect Name Thieves
		if ((defined($config->{'ban_name_thieves'})) && ($config->{'ban_name_thieves'})) {
		    my $i;
		    my $stripped_compare;
		    my $stripped_old = &strip_color($name_by_slot{$slot});
		    my $stripped_new = &strip_color($name);
		    my $old_name_stolen = 0;
		    my $new_name_stolen = 0;
		    foreach $i (keys %name_by_slot) {
			if (($name_by_slot{$i} ne 'SLOT_EMPTY') && ($slot ne $i)) {
			    $stripped_compare = &strip_color($name_by_slot{$i});	
			    # Compare the old name for matches
			    if ($name_by_slot{$slot} eq $name_by_slot{$i}) { $old_name_stolen = 1; }
			    elsif ($name_by_slot{$slot} eq $stripped_compare) { $old_name_stolen = 1; }
			    elsif ($stripped_old eq $name_by_slot{$i}) { $old_name_stolen = 1; }
			    elsif ($stripped_old eq $stripped_compare) { $old_name_stolen = 1; }  
			    # Compare the new name for matches
			    if ($name eq $name_by_slot{$i}) { $new_name_stolen = 1; }
			    elsif ($name eq $stripped_compare) { $new_name_stolen = 1; }
			    elsif ($stripped_new eq $name_by_slot{$i}) { $new_name_stolen = 1; }
			    elsif ($stripped_new eq $stripped_compare) { $new_name_stolen = 1; }
			}
		    }
		    if (($old_name_stolen) && ($new_name_stolen)) {
			&rcon_command("say " . '"^1ОБНАРУЖЕНА КРАЖА НИКНЕЙМОВ:"' . "^3Slot \#^2 $slot" . '"^7был перманентно забанен за кражу никнеймов!"');
			my $ban_name = 'NAME STEALING JERKASS';
			my $ban_ip = 'undefined';
			my $ban_guid = '12345678';
			my $unban_time = 2125091758;
			if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) { $ban_ip = $ip_by_slot{$slot}; }
			if ($guid_by_slot{$slot}) { $ban_guid = $guid_by_slot{$slot}; }
			&rcon_command("clientkick $slot");
			&log_to_file('logs/kick.log', "BAN: NAME_THIEF: $ban_ip / $guid_by_slot{$slot} was permanently for being a name thief:  $name / $name_by_slot{$slot} ");
			$bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
			$bans_sth->execute($time, $unban_time, $ban_ip, $ban_guid, $ban_name) or &die_nice("Unable to do insert\n");					
		    }  
		}
		# End of Name Thief Detection
	    }
	}
	$name_by_slot{$slot} = $name;
    }
}

# /rcon scr_friendlyfire <0/1/2/3>  0 = friendly fire off, 1=friendly fire on, 2=reflect damage, 3=shared.
# BEGIN: !friendlyfire_command($state)
sub friendlyfire_command {
    my $state = shift;
    if (&flood_protection('friendlyfire', 30, $slot)) { return 1; }
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
        &rcon_command("scr_friendlyfire 1");
	    $friendly_fire = 1;
        &rcon_command("say " . '"Админ ^1ВКЛЮЧИЛ ^7Огонь по союзникам. Будьте аккуратны, старайтесь не ранить своих товарищей по команде"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED by:  $name - GUID $guid");
    }
	elsif ($state =~ /^(off|0|no|disabled?)$/i) {
        &rcon_command("scr_friendlyfire 0");
        $friendly_fire = 0;
        &rcon_command("say " . '"Админ ^2ВЫКЛЮЧИЛ ^7Огонь по союзникам"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was DISABLED by:  $name - GUID $guid");
    }
	elsif ($state =~ /^2$/i) {
        &rcon_command("scr_friendlyfire 2");
	    $friendly_fire = 2;
        &rcon_command("say " . '"Админ ^1ВКЛЮЧИЛ ^7Огонь по союзникам с рикошетным уроном"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED with reflective team damage by:  $name - GUID $guid");
    }
	elsif ($state =~ /^3$/i) {
        &rcon_command("scr_friendlyfire 3");
        $friendly_fire = 3;
        &rcon_command("say " . '"Админ ^1ВКЛЮЧИЛ ^7Огонь по союзникам с совместным уроном"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED with shared team damage by:  $name - GUID $guid");
    }
	else { &rcon_command("say " . '"Неверное значение команды !friendlyfire. Доступны значения от 0 до 3"'); }
}
# END: &friendlyfire_command

#BEGIN:  &make_affiliate_server_announcement
sub make_affiliate_server_announcement {
    my $line;
    my $server;
    my $hostname = 'undefined';
    my $clients = 0;
    my $gametype = 'undefined';
    my $maxclients = 0;
    my $mapname = 'undefined';
    my @results;
    my @info_lines;
    foreach $server (@affiliate_servers) {
	$hostname = 'undefined';
	$clients = 0;
	$gametype = 'undefined';
	$maxclients = 0;
	$mapname = 'undefined';
	$line = &get_server_info($server);
	@info_lines = split(/\n/, $line);
	foreach $line (@info_lines) {
	    $line =~ s/\s+$//;
	    if ($line =~ /^hostname: (.*)/) {
		$hostname = $1;
		$servername_cache{$server} = $hostname;
	    }
	    if ($line =~ /^clients: (.*)/) { $clients = $1; }
	    if ($line =~ /^gametype: (.*)/) {
		$gametype = $1;
		if (defined($description{$gametype})) { $gametype = $description{$gametype}; }
	    }
	    if ($line =~ /^sv_maxclients: (.*)/) { $maxclients = $1; }
	    if ($line =~ /^mapname: (.*)/) {
		$mapname = $1;
		if (defined($description{$mapname})) { $mapname = $description{$mapname}; }
	    }
	}
	if ($clients) {
	    if ($clients == 1 or $clients == 21 or $clients == 31)
		{ $line = "^1$clients " . '"^7игрок на"' . " ^7$hostname  ^7(^3$mapname^7/^5$gametype^7)\n"; }
		elsif ($clients == 2 or $clients == 3 or $clients == 4 or $clients == 22 or $clients == 23 or $clients == 24 or $clients == 32)
		{ $line = "^1$clients " . '"^7игрока на"' . " ^7$hostname  ^7(^3$mapname^7/^5$gametype^7)\n"; }
	    else { $line = "^1$clients " . '"^7игроков на"' . " ^7$hostname  ^7(^3$mapname^7/^5$gametype^7)\n"; }
	    if ($clients < $maxclients) { push @results, $line; }
	}
    }
    if (defined($results[0])) {
	&rcon_command("say " . $affiliate_server_prenouncements[int(rand(7654321) * $#affiliate_server_prenouncements)]);
	sleep 1;
	foreach $line (@results) { &rcon_command("say $line"); }
    }
}
# END: &make_affiliate_server_announcement

# BEGIN: &get_server_info($ip_address)
sub get_server_info {
    my $ip_address = shift;
    my $total_tries = 3; # The total number of attempts to get an answer out of the server.
    my $read_timeout = 1; # Number of seconds per attempt to wait for the response packet.
    my $port = 28960;
    my $d_ip;
    my $message;
    my $current_try = 0;
    my $still_waiting = 1;
    my $got_response = 0;
    my $maximum_lenth = 200;
    my $portaddr;
    my ($session_id, $result, $reason, $guid);
    my $pause_when_done;
    my %infohash;
    my $return_text = '';
    if ($ip_address =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\:(\d{1,5})$/) { ($ip_address,$port) = ($1,$2); }
    if ((!defined($ip_address)) or ($ip_address !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) { return "IP Address format error"; }
    socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp")) or return "Socket error: $!";
    my $send_message = "\xFF\xFF\xFF\xFFgetinfo xxx";
    $d_ip = inet_aton($ip_address);
    my $selecta = IO::Select->new;
    $selecta->add(\*SOCKET);
    my @ready;
    while (($current_try++ < $total_tries) && ($still_waiting)) {
	# Send the packet
	$portaddr = sockaddr_in($port, $d_ip);
	send(SOCKET, $send_message, 0, $portaddr) == length($send_message) or &die_nice("cannot send to $ip_address($port): $!\n\n");
	# Check to see if there is a response yet.
	@ready = $selecta->can_read($read_timeout);
	if (defined($ready[0])) {
	    # Yes, the socket is ready.
	    $portaddr = recv(SOCKET, $message, $maximum_lenth, 0) or &die_nice("Socket error: recv: $!");
	    # strip the 4 \xFF bytes at the begining.
	    $message =~ s/^.{4}//;
	    $got_response = 1;
	    $still_waiting = 0;
	}
    }
    if ($got_response) {
	if ($message =~ /infoResponse/) {
	    $message = substr($message,14,length($message));
	    my @parts = split(/\\/, $message);
	    my $value;
	    while (@parts) {
		$value = shift(@parts);
		$infohash{$value} = shift(@parts);
	    }
	    foreach (sort {$a cmp $b} keys %infohash) { $return_text .= "$_: " . $infohash{$_} . "\n"; }
	}
    }
	else {
	print "\nERROR:\n\t$ip_address:$port is not currently responding to requests.\n";
	print "\n\tSorry.  Try again later.\n\n";
    }
    return $return_text;
}
# END: &get_server_info($ip_address)

# BEGIN: &broadcast_message($message)
sub broadcast_message {
    my $message = shift;
    if ((!defined($message)) or ($message !~ /./)) { return; }
    my $num_servers = 0;
    my $config_val;
    my $ip_address;
    my $port;
    my $password;
    my $rcon;
    $message = "say ^1[^7$name^2\@^3$server_name^1]^7: $message";
    foreach $config_val (@remote_servers) {
	if ($config_val =~ /^([\d\.]+):(\d+):(.*)/) {
	    ($ip_address,$port,$password) = ($1,$2,$3);
	    $num_servers++;
	    $rcon = new KKrcon (Host => $ip_address, Port => $port, Password => $password, Type => 'old');
	    print $rcon->execute($message); 
	}
	else { print "WARNING: Invalid remote_server syntax: $config_val\n"; }
    }
    if ($num_servers == 0) { &rcon_command("say " . '"К сожалению, не найдено настроенных удаленных серверов. Проверьте ваш конфигурационный файл."'); }
    elsif ($num_servers == 1) { &rcon_command("say " . '"Ваше сообщение было успешно передано на другой сервер."'); }
    else { &rcon_command("say " . '"Ваше сообщение было успешно передано на"' . "^1$num_servers" . '"других серверов"'); }
}

# BEGIN: big_red_button_command
sub big_red_button_command {
    &rcon_command("say " . '"О НЕТ, он нажал ^1КРАСНУЮ КНОПКУ^7!!!!!!!"');
    sleep 1;
    &rcon_command("kick all");
    &log_to_file('logs/kick.log', "!KICK: All Players were kicked by $name - GUID $guid - via !nuke command");
}