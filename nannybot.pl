#!/usr/bin/perl -w

# debug message
print "Initializing NannyBot...\n";
sleep 1;

my $version = '3.0.9 RU';

# VERSION 3.xx RU changelog is on github page https://github.com/voron00/Nanny/commits/master

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
#  ability to specify tempban time via config?  (sv_kickbantime 300)
#
#  Command wish list:
#  !teambalance on/off ...done
#  !forcerespawn on/off ...done
#  !spectatefree on/off ...done
#  !rifles on/off/only
#  !bolt on/off/only
#  !mgs on/off/only


# NOTE:  rcon names have full color codes, kill lines have full colors, chat lines do not.


# List of modules
use warnings; # helps catch failure strings.
use strict;   # strict keeps us from making stupid typos.
use Rcon::KKrcon;   # The KKrcon module used to issue commands to the server
# use IO::File; # IO-File is used for raw disk reads. No need for now
use Carp::Heavy;  # DBI seems to need this.  Perl2Exe Needs help, apparently.
use DBD::SQLite; # Perl2EXE is happier if we declare this.
# use DBD::mysql; # Support for MySQL based logging. Temporarily disabled
use DBI; # database
use Geo::IP; # GeoIP is used for locating IP addresses.
use Geo::Inverse; # Used for calculating the distance from the server
use Time::Duration; # expresses times in plain english
use Socket; # Used for asking activision for GUID numbers for sanity check.
use IO::Select; # also used by the udp routines for manual GUID lookup
use LWP::Simple; # HTTP fetches are used for the dictionary
use Net::FTP; # FTP support for remote logfiles
use File::Basename; # ftptail support
use File::Temp qw/ :POSIX /; # ftptail support
use Carp; # ftptail support

# Connect to sqlite databases
#my $region_names_dbh = DBI->connect("dbi:SQLite:dbname=databases/region_names.db","","");
my $guid_to_name_dbh = DBI->connect("dbi:SQLite:dbname=databases/guid_to_name.db","","");
my $ip_to_guid_dbh = DBI->connect("dbi:SQLite:dbname=databases/ip_to_guid.db","","");
my $ip_to_name_dbh = DBI->connect("dbi:SQLite:dbname=databases/ip_to_name.db","","");
my $seen_dbh = DBI->connect("dbi:SQLite:dbname=databases/seen.db","","");
my $stats_dbh = DBI->connect("dbi:SQLite:dbname=databases/stats.db","","");
my $bans_dbh = DBI->connect("dbi:SQLite:dbname=databases/bans.db","","");
my $definitions_dbh = DBI->connect("dbi:SQLite:dbname=databases/definitions.db","","");
my $mysql_logging_dbh;

# Global variable declarations
my $idlecheck_interval = 45;
my %idle_warn_level;
my $namecheck_interval = 60;
my %name_warn_level;
my $last_namecheck;
my $rconstatus_interval = 27;
my $guid_sanity_check_interval = 100;
my $problematic_characters = "\x86|\x99|\xAE|\xBB|\xAB";
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
my %ip_by_slot;
my %guid_by_slot;
my %spam_last_said;
my %spam_count;
my $seen_sth;
my $stats_sth;
my %last_ping;
my %ping_average;
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
my $game_type = '';
my $game_name = '';
my $map_name = '';
my $friendly_fire = 0;
my $kill_cam = 1;
my $cod_version = '';
my $server_name = '';
my $max_clients = 999;
my $max_ping = 999;
my $private_clients = 0;
my $pure = 1;
my $voice = 0;
my $last_guid0_audit = time;
my $guid0_audit_interval = 70;
my %ignore;
my $ftp_lines = 0;
my $ftp_sleepInterval = 1;
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
my $ftp; # the ftp control object
my $mysql_chat_insert_sth;
my $mysql_nextmap_sth;
my $next_map = '';
my $next_gametype = '';
my $freshen_next_map_prediction = 1;
my $temporary;
my %description;
my $next_mysql_repair;
my $mysql_repair_interval = 137;
my $mysql_is_broken = 1;
my $now_upmins = 0;
my $last_upmins = 0;
my @affiliate_servers;
my @affiliate_server_prenouncements;
my $next_affiliate_announcement;
my %servername_cache;
my @remote_servers;

# if local ip address
my $localip = '127.0.0.1';

# print current perl version (debug message)
print "Perl runtime version is $^V, running on $^O\n";

# initialize time, print and format it
my @weekday = ("Sunday", "Monday", "Tuesday", "Wednsday", "Thursday", "Friday", "Saturday");
my $retval = time();
print "Reading time values from the system...\n";
my $local_time = localtime($retval);
print "Local time = $local_time\n";
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year = $year + 1900;
$mon += 1;
print "Formated time = $mday/$mon/$year $hour:$min:$sec $weekday[$wday]\n";

# turn on auto-flush for STDOUT
$| = 1;

# shake the snow-globe.
srand;

# End of global variable declarations

# Read the configuration from the .cfg file.
&load_config_file('nanny.cfg');

# Open the server logfile for reading.
if ($logfile_mode eq 'local') {
    &open_server_logfile($config->{'server_logfile_name'});
    # Seek to the end of the logfile
    &seek_to_end();    
} elsif ($logfile_mode eq 'ftp') {
    # initialize FTP connection here.
    fileparse_set_fstype(); # FTP uses UNIX rules
    $ftp_tmpFileName = tmpnam();
    $ftp_verbose && warn "FTP $ftp_host\n";
    $ftp=Net::FTP->new($ftp_host,Timeout=>240) || &die_nice("FTP: Cannot ftp to $ftp_host: $!");
    $ftp_verbose && warn "USER: " . $config->{'ftp_username'} . " \t PASS: ". '*'x length($config->{'ftp_password'}). "\n"; # hide password
    $ftp->login($config->{'ftp_username'},$config->{'ftp_password'}) || &die_nice("FTP: Can't login to $ftp_host: $!");
    $ftp_verbose && warn "CWD: $ftp_dirname\n";
    $ftp->cwd($ftp_dirname) or &die_nice("FTP: Can't cd  $!");
    
    if ($config->{'use_passive_ftp'}) {
	print "Using PASV ftp mode...\n\n";
	$ftp->pasv() || die $ftp->message;
    }
    $ftp_lines && &ftp_getNlines;
    $ftp_type = $ftp->binary;
    $ftp_lastEnd = $ftp->size($ftp_basename) || &die_nice("ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n");
    $ftp_verbose && warn "SIZE $ftp_basename: " . $ftp_lastEnd . " bytes\n";
}

# Initialize the database tables if they do not exist
&initialize_databases();

# initialize the timers
$time = time;
$last_idlecheck = $time;
$last_rconstatus = 0;
$last_namecheck = $time;
$last_guid_sanity_check = $time;
$timestring = scalar(localtime($time));
$next_announcement = $time + 120;
$next_mysql_repair = $time + $mysql_repair_interval;
$next_affiliate_announcement = $time;


# create the rcon control object - this is how we send commands to the console
my $rcon = new KKrcon(
		      Host => $config->{'ip'},
		      Port => $config->{'port'},
		      Password => $config->{'rcon_pass'},
		      Type => 'old'
);

# tell the server that we want the game logfiles flushed to disk after every line.
&rcon_query("g_logSync 1");
print "Synchronizing logfile...\n";
sleep 1;

# Ask the server if voting is currently turned on or off
my $voting_result = &rcon_query("g_allowVote");
if ($voting_result =~ /\"g_allowVote\" is: \"(\d+)\^7\"/m) {
    $voting = $1;
    if ($voting) { print "Voting is currently turned ON\n"; }
    else { print "Voting is currently turned OFF\n"; }
} else {
    print "sorry, cant parse the g_allowVote results.\n";
}

# Ask the server what it's official name is
$voting_result = &rcon_query("sv_hostname");
if ($voting_result =~ /\"sv_hostname\" is: \"([^\"]+)\"/m) {
    $server_name = $1;
    $server_name =~ s/\^7$//;
    if ($server_name =~ /./) { print "Server Name is: $server_name\n"; }
} else {
    print "WARNING: cant parse the sv_hostname results.\n";
}



# Depending on the OS, either write the pid file or a batch file for shuttind down nanny via pskill.exe
#if ($^O eq 'MSWin32') {
#    open (BATCH, "> shutdown_nannybot.bat") || print "Warning: couldn't write shutdown_nannybot.bat\n";
#    print BATCH "pskill.exe $$\n";
#    close (BATCH);
#} else {
#    open (BATCH, "> nannybot.pid") || print "Warning: couldn't write nannybot.pid\n";
#    print BATCH "$$";
#    close (BATCH);    
#}

# Main Loop
while (1) {

    if ($logfile_mode eq 'local') {
	$line = <LOGFILE>;
    } elsif ($logfile_mode eq 'ftp') {
	$line = &ftp_get_line();
    }

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
			$ip_by_slot{$reset_slot} = 'SLOT_EMPTY';
			$guid_by_slot{$reset_slot} = 0;
			$spam_count{$reset_slot} = 0;
			$last_ping{$reset_slot} = 0;
			$ping_average{$reset_slot} = 0;
			$penalty_points{$reset_slot} = 0;
			$last_killed_by{$reset_slot} = '... ummm .... Sorry, I forgot.';
			$kill_spree{$reset_slot} = 0;
			$best_spree{$reset_slot} = 0;
			$ignore{$reset_slot} = 0;
		    }
		    &rcon_command("say " , '"^1*** ^2Похоже что сервер упал, перезапускаю себя... ^1***"');
		    # sleep 1;
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

		# my $i = $attacker_name;
		# $i =~ s/[\w\^\{\}\s\|\*\-\[\]\(\)\.\:\!\']//g;
		# if (length($i)) { print "DEBUG: Unknown Ascii Character: $i: $attacker_name: " . ord($i) . "\n"; }


		if ($attacker_guid) { &cache_guid_to_name($attacker_guid, $attacker_name); }
		if ($victim_guid) { &cache_guid_to_name($victim_guid, $victim_name); }
		$last_activity_by_slot{$attacker_slot} = $time;

		&update_name_by_slot($attacker_name, $attacker_slot);
		&update_name_by_slot($victim_name, $victim_slot);

		$guid_by_slot{$attacker_slot} = $attacker_guid;
		$guid_by_slot{$victim_slot} = $victim_guid;
		$last_killed_by{$victim_slot} = $attacker_name;
		
		# Glitch Server Mode.   Beat the Germans down.
		if ($config->{'glitch_server_mode'}) {
		    if (($attacker_team eq 'axis') && ($victim_team eq 'allies')) {
			print "Murderer:  " . &strip_color($attacker_name) . " killed someone.  Kicking!\n";
			&rcon_command("say ^1" . $attacker_name . ":^1 " . $config->{'glitch_kill_kick_message'});
			print &strip_color($attacker_name) . ": " . $config->{'glitch_kill_kick_message'} . "\n"; 
			sleep 1;
			&rcon_command("clientkick $attacker_slot");
			&log_to_file('logs/kick.log', "GLITCH_KILL: Murderer!  Kicking $attacker_name for being german and killing an allie");
		    }
		}

		# Track the kill stats for the killer
		# checking the attacker teams ensures we dont try to count suicides, those that are auto-balanced, or deaths from falling
		if (($attacker_team eq 'axis') || ($attacker_team eq 'allies') || (($attacker_team eq '') && ($damage_type ne 'MOD_SUICIDE'))) {
		    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE name=?");
		    $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		    @row = $stats_sth->fetchrow_array;
		    if ($row[0]) {
			if ($damage_location eq 'head') {
			    $stats_sth = $stats_dbh->prepare("UPDATE stats SET kills=?,headshots=? WHERE name=?");
			    $stats_sth->execute(($row[2] + 1), ($row[4] + 1 ), &strip_color($attacker_name)) or &die_nice("Unable to do update\n");
			} else {
			    $stats_sth = $stats_dbh->prepare("UPDATE stats SET kills=? WHERE name=?");
			    $stats_sth->execute(($row[2] + 1), &strip_color($attacker_name)) or &die_nice("Unable to do update\n");
			}
		    }
		    else {
			$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?)");
			if ($damage_location eq 'head') {
			    $stats_sth->execute(&strip_color($attacker_name), 1, 0, 1) or &die_nice("Unable to do insert\n");
			} else {
			    $stats_sth->execute(&strip_color($attacker_name), 1, 0, 0) or &die_nice("Unable to do insert\n");
			}
		    }
		    
		    # 2nd generation stats
		    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats2 WHERE name=?");
                    $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
                    @row = $stats_sth->fetchrow_array;
                    if ($row[0]) { }
                    else {
                        $stats_sth = $stats_dbh->prepare("INSERT INTO stats2 VALUES (NULL, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)");
			$stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to do insert\n");
                    }

# name,pistol_kills,grenade_kills,bash_kills,shotgun_kills,sniper_kills,rifle_kills,machinegun_kills,best_killspree,nice_shots,bullshit_shots
		    # Grenade Kills
		    if ($damage_type eq 'MOD_GRENADE_SPLASH') {
			$stats_sth = $stats_dbh->prepare("UPDATE stats2 SET grenade_kills = grenade_kills + 1 WHERE name=?");
                        $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats2\n");
			# print "DEBUG: Added a grenade kill for: $attacker_name\n"; 
		    }

		    # Pistol Kills
		    if ($attacker_weapon =~ /^(webley|colt|luger|TT30)_mp$/) {
			$stats_sth = $stats_dbh->prepare("UPDATE stats2 SET pistol_kills = pistol_kills + 1 WHERE name=?");
                        $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats2\n");
                        # print "DEBUG: Added a pistol kill for: $attacker_name\n";
		    }
		    
		    # Bash / Melee Kills
                    if ($damage_type eq 'MOD_MELEE') {
                        $stats_sth = $stats_dbh->prepare("UPDATE stats2 SET bash_kills = bash_kills + 1 WHERE name=?");
                        $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats2\n");
                        # print "DEBUG: Added a bash kill for: $attacker_name\n";
                    }

                    # Shotgun Kills
                    if ($attacker_weapon eq 'shotgun_mp') {
                        $stats_sth = $stats_dbh->prepare("UPDATE stats2 SET shotgun_kills = shotgun_kills + 1 WHERE name=?");
                        $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats2\n");
                        # print "DEBUG: Added a shotgun kill for: $attacker_name\n";
                    }

                    # Sniper Kills
                    if ($attacker_weapon =~ /^(enfield_scope|springfield|mosin_nagant_sniper|kar98k_sniper)_mp$/) {
                        $stats_sth = $stats_dbh->prepare("UPDATE stats2 SET sniper_kills = sniper_kills + 1 WHERE name=?");
                        $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats2\n");
                        # print "DEBUG: Added a sniper kill for: $attacker_name\n";
                    }

                    # Rifle Kills
                    if ($attacker_weapon =~ /^(enfield|m1garand|m1carbine|mosin_nagant|SVT40|kar98k|g43)_mp$/) {
                        $stats_sth = $stats_dbh->prepare("UPDATE stats2 SET rifle_kills = rifle_kills + 1 WHERE name=?");
                        $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats2\n");
                       # print "DEBUG: Added a rifle kill for: $attacker_name\n";
                    }
		    
		    #  Machinegun Kills
                    if ($attacker_weapon =~ /^(sten|thompson|bren|greasegun|bar|PPS42|ppsh|mp40|mp44|30cal_stand|mg42_bipod_stand)_mp$/) {
                        $stats_sth = $stats_dbh->prepare("UPDATE stats2 SET machinegun_kills = machinegun_kills + 1 WHERE name=?");
                        $stats_sth->execute(&strip_color($attacker_name)) or &die_nice("Unable to update stats2\n");
                      #  print "DEBUG: Added a machine-gun kill for: $attacker_name\n";
                    }		    

		    # End 2nd generation stats

		}
		
		# Track the death stats for the victim
		# checking the attacker team ensures we don't count deaths from switching teams or changing to spectator
		if (($attacker_team eq 'axis') || ($attacker_team eq 'allies') || ($attacker_team eq 'world') || 
		  (($attacker_team eq '') && ($damage_type ne 'MOD_SUICIDE'))) {
		    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE name=?");
		    $stats_sth->execute(&strip_color($victim_name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
		    @row = $stats_sth->fetchrow_array;
		    if ($row[0]) {
			$stats_sth = $stats_dbh->prepare("UPDATE stats SET deaths=? WHERE name=?");
			$stats_sth->execute(($row[3] + 1), &strip_color($victim_name)) or &die_nice("Unable to do update\n");
		    }
		    else {
			$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?)");
			$stats_sth->execute(&strip_color($victim_name), 0, 1, 0) or &die_nice("Unable to do insert\n");
		    }
		}
		# End of kill-stats tracking
		
		# print the kill to the screen
		if (($damage_location eq 'head') && ($config->{'show_headshots'})) { 
		    print "HEADSHOT: " . &strip_color($attacker_name) . " killed " . &strip_color($victim_name) . " - HEADSHOT!\n";
		} else {
		    if ($config->{'show_kills'}) {
			if ($victim_slot == $attacker_slot) {
			    print "SUICIDE: " . &strip_color($attacker_name) . " blew themself up.\n";
			} elsif ($damage_type eq 'MOD_FALLING') {
			    print "FALL: " . &strip_color($victim_name) . " fell to their death.\n";
			}
			else {
			    print "KILL: " . &strip_color($attacker_name) . " killed " . &strip_color($victim_name) . "\n";
			}
		    }
		}

		# First Blood
		if (
		    ($config->{'first_blood'}) && 
		    ($first_blood == 0) && 
		    ($attacker_slot ne $victim_slot) &&
		    ($attacker_slot >= 0)
		    ) {		    
		    $first_blood = 1;
		    &rcon_command("say " . '"^3ПЕРВАЯ КРОВЬ:"' . "^1$attacker_name^7" . '"убил"' . "^2$victim_name^7");
		    print "FIRST BLOOD: $attacker_name killed $victim_name\n"; 
		    # sleep 1;
		}
		
		# Killing Spree
		if (($config->{'killing_sprees'}) && ($damage_type ne 'MOD_SUICIDE') && ($attacker_slot ne $victim_slot)) {
		    if (!defined($kill_spree{$attacker_slot})) {
			$kill_spree{$attacker_slot} = 1;
		    } else {
			$kill_spree{$attacker_slot} += 1;
		    } 
		    if (defined($kill_spree{$victim_slot})) {
			# print "KILLSPREE: $victim_name had killed $kill_spree{$victim_slot} people in a row\n";
			if (!defined($best_spree{$victim_slot})) { $best_spree{$victim_slot} = 0; }
			if (($kill_spree{$victim_slot} > 2) && ($kill_spree{$victim_slot} > $best_spree{$victim_slot})) {
			    $best_spree{$victim_slot} = $kill_spree{$victim_slot};  
			    $stats_sth = $stats_dbh->prepare("SELECT best_killspree FROM stats2 WHERE name=?");
			    $stats_sth->execute(&strip_color($victim_name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
			    @row = $stats_sth->fetchrow_array;
			    if ((defined($row[0])) && ($row[0] < $best_spree{$victim_slot})) {
				$stats_sth = $stats_dbh->prepare("UPDATE stats2 SET best_killspree=? WHERE name=?");
				$stats_sth->execute($best_spree{$victim_slot}, &strip_color($victim_name)) 
				or &die_nice("Unable to update stats2\n");
				&rcon_command("say ^1$attacker_name^7" . '"остановил серию убийств игрока"' . "^2$victim_name^7" . '"который убил"' . "^1$kill_spree{$victim_slot}^7" . '"человек"');
			    } else {
				&rcon_command("say ^1$attacker_name^7" . '"остановил серию убийств игрока"' . "^2$victim_name^7" . '"который убил"' . "^1$kill_spree{$victim_slot}^7" . '"человек"');
				}
			    # sleep 1;
			}
		    }
		    $kill_spree{$victim_slot} = 0;
		}
		# End of Kill-Spree section
		
	
		
	    } else { print "WARNING: unrecognized syntax for kill line:\n\t$line\n"; }
	}
	elsif ($first_char eq 'D') {
	    # A "DAMAGE" event has happened.
	    if ($line =~ /^D;(\d+);(\d+);(allies|axis|);([^;]+);(\d*);([\d\-]+);(allies|axis|world|spectator|);([^;]*);(\w+);(\d+);(\w+);(\w+)/) {
		($victim_guid, $victim_slot, $victim_team, $victim_name, $attacker_guid, $attacker_slot, $attacker_team,
		 $attacker_name, $attacker_weapon, $damage, $damage_type, $damage_location) = ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12);
		$attacker_name =~ s/$problematic_characters//g;
                $victim_name =~ s/$problematic_characters//g;
		if ($attacker_guid) { &cache_guid_to_name($attacker_guid, $attacker_name); }
		if ($victim_guid) { &cache_guid_to_name($victim_guid, $victim_name); }
		$last_activity_by_slot{$attacker_slot} = $time;
                &update_name_by_slot($attacker_name, $attacker_slot);
                &update_name_by_slot($victim_name, $victim_slot);
		$guid_by_slot{$attacker_slot} = $attacker_guid;
		$guid_by_slot{$victim_slot} = $victim_guid;
		
	    } else { print "WARNING: unrecognized syntax for damage line:\n\t$line\n"; }
	}
	elsif ($first_char eq 'J') {
	    # A "JOIN" Event has happened
	    # WARNING:  This join does not only mean they just connected to the server
	    #     it can also mean that the level has changed.
	    if ($line =~ /^J;(\d+);(\d+);(.*)/) {
		($guid,$slot,$name) = ($1,$2,$3);
		# cache the guid and name
		if ($guid) {
		    &cache_guid_to_name($guid,$name);
		    $most_recent_guid = $guid;
		    $most_recent_slot = $slot;
		    $most_recent_time = $time;
		}
		$last_activity_by_slot{$slot} = $time;
		$idle_warn_level{$slot} = 0;
		$guid_by_slot{$slot} = $guid;
		&update_name_by_slot($name, $slot);
		$spam_count{$slot} = 0;
		$ip_by_slot{$slot} = 'not_yet_known';
		$last_ping{$slot} = 0;
		$ping_average{$slot} = 0;
		$penalty_points{$slot} = 0;
		# $ignore{$slot} = 0;

		if ($config->{'show_game_joins'}) {
			&rcon_command("say " . '"Игрок "' . "$name" . '" ^7присоединился к игре"');
		}
		if ($config->{'show_joins'}) {
		    print "JOIN: " . &strip_color($name) . " has joined the game\n";
		}
	    } else { print "WARNING: unrecognized syntax for join line:\n\t$line\n"; }
	} 
	elsif ($first_char eq 'Q') {
	    # A "QUIT" Event has happened
	    if ($line =~ /^Q;(\d+);(\d+);(.*)/) {
		($guid,$slot,$name) = ($1,$2,$3);
		# cache the guid and name
		if ($guid) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = 'gone';
		$idle_warn_level{$slot} = 0;
		&update_name_by_slot('SLOT_EMPTY', $slot);
		$ip_by_slot{$slot} = 'SLOT_EMPTY';
		$guid_by_slot{$slot} = 0;
		$spam_count{$slot} = 0;
                $last_ping{$slot} = 0;
                $ping_average{$slot} = 0;
		$penalty_points{$slot} = 0;
		$last_killed_by{$slot} = '... ummm .... Sorry, I forgot.';
		$kill_spree{$slot} = 0;
		$best_spree{$slot} = 0;
		$ignore{$slot} = 0;

		# populate the !seen data
		$seen_sth = $seen_dbh->prepare("UPDATE seen SET time=? WHERE name=?");
		$seen_sth->execute($time,$name) or &die_nice("Unable to do update\n");
		# end of !seen data population
		
        if ($config->{'show_quits'}) {
		    print "QUIT: " . &strip_color($name) . " has left the game\n";
		}
		if ($config->{'show_game_quits'}) {
			&rcon_command("say " . '"Игрок "' . "$name" . '" ^7покинул игру"');
		}
	    } else { print "WARNING: unrecognized syntax for quit line:\n\t$line\n"; }
	    
	}
	elsif ($first_char eq 's') {
	    # say / sayteam
	    if ($line =~ /^say;(\d+);(\d+);([^;]+);(.*)/) {
		# a "SAY" event has happened
		($guid,$slot,$name,$message) = ($1,$2,$3,$4);
		if ($guid) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = $time;
		&update_name_by_slot($name, $slot);
		$guid_by_slot{$slot} = $guid;
		$message =~ s/^\x15//;
		&chat();
	    } elsif ($line =~ /^sayteam;(\d+);(\d+);([^;]+);(.*)/) {
		# a "SAYTEAM" event has happened
		($guid,$slot,$name,$message) = ($1,$2,$3,$4);
		if ($guid) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = $time;
		&update_name_by_slot($name, $slot);
		$guid_by_slot{$slot} = $guid;
		$message =~ s/^\x15//;
		if ($message !~ /QUICKMESSAGE_/) {
		    &chat();
		}
	    } #else { print "WARNING: unrecognized syntax for say line:\n\t$line\n"; }
	    
	}
	elsif ($first_char eq 't') {
            # say / sayteam
            if ($line =~ /^tell;(\d+);(\d+);([^;]+);\d+;\d+;[^;]+;(.*)/) {
                # a "tell" (private message) event has happened
                ($guid,$slot,$name,$message) = ($1,$2,$3,$4);
                if ($guid) { &cache_guid_to_name($guid,$name); }
                $last_activity_by_slot{$slot} = $time;
                &update_name_by_slot($name, $slot);
                $guid_by_slot{$slot} = $guid;
                $message =~ s/^\x15//;
                &chat();
            } else { print "WARNING: unrecognized syntax for tell line:\n\t$line\n"; }

        }
	elsif ($first_char eq 'W') {
	    if ($line =~ /^Weapon;(\d+);(\d+);([^;]*);(\w+)$/) {
		# a "WEAPON" Event has happened
		($guid,$slot,$name,$weapon) = ($1,$2,$3,$4);
		# cache the guid and name
		if ($guid) { &cache_guid_to_name($guid,$name); }
		$last_activity_by_slot{$slot} = $time;
		&update_name_by_slot($name, $slot);
		$guid_by_slot{$slot} = $guid;
	    } elsif ($line =~ /^W;([^;]*);(\d+);([^;]*)/) {
		# a "Round Win" Event has happened
		($attacker_team,$guid,$name) = ($1,$2,$3);
		if ((defined($attacker_team)) && ($attacker_team =~ /./)) {
		    print "GAME OVER: $attacker_team have WON this game of $game_type on $map_name\n"; 
		} else  {
		    print "GAME OVER: $name has WON this game of $game_type on $map_name\n";
		}

		# Buy some time so we don't do an rcon status during a level change
		$last_rconstatus = $time;

		# cache the guid and name
		if ($guid) { &cache_guid_to_name($guid,$name); }
		# prepare for First Blood
		$first_blood = 0;
		# anti-vote-rush
		# first, look up the game-type so we can exempt S&D
		if ($game_type eq 'none') {
		    $game_type = &rcon_query('g_gametype');
		    if ($game_type =~ /\"g_gametype\" is: \"(\w+)\^7\"/m) {
			$game_type = $1;
		    } else {
			print "WARNING: unable to parse game_type:  $game_type\n"; 
		    }
		}
		print "DEBUG: game_type is: $game_type\n";
		if (($voting) && ($config->{'anti_vote_rush'}) && ($game_type ne 'sd')) {
		    print "ANTI-VOTE-RUSH:  Turned off voting for 25 seconds...\n";
		    &rcon_command("g_allowvote 0");
		    # sleep 1;
		    $reactivate_voting = $time + 25;
		}
	    } else {
		print "WARNING: unrecognized syntax for Weapon/Round Win line:\n\t$line\n";
	    }
	}
	elsif ($first_char eq 'L') {
	    # Round Losers
	    if ($line =~ /^L;([^;]*);(\d+);([^;]*)/) {
		($attacker_team,$guid,$name) = ($1,$2,$3);
		if ((defined($attacker_team)) && ($attacker_team =~ /./)) {
		    print "GAME OVER: $attacker_team have LOST this game of $game_type on $map_name\n";
		} else { print "... apparently there are no losers\n"; }
	    } else { 
		print "WARNING: unrecognized syntax for Round Loss line:\n\t$line\n";
	    }
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
	    
	    $freshen_next_map_prediction = 1;
	    $last_rconstatus = 0;
	}
	elsif ($first_char eq 'S') {
	    # Server Shutdown - Triggers when the server shuts down?
	    # print "$line\n";
	}
	elsif ($first_char eq '-') {
	    # Line Break
	}
	elsif ($first_char eq 'E') {
	    # Exit level - what is the difference between this and a shutdown? 
	    # This happens much less frequently than a Shutdown Game event.
	    # This may be a game server shutdown, not just a level ending.
	    # print "$line\n";
	}
	elsif ($first_char eq 'A') {
	    if ($line =~ /^A;(\d+);(\d+);(\w+);(.*);bomb_plant/) {
		($guid,$slot,$attacker_team,$name) = ($1,$2,$3,$4);
		print "BOMB: $name \[$attacker_team\] planted the bomb.\n"; 
	    } elsif ($line =~ /^A;(\d+);(\d+);(\w+);(.*);bomb_defuse/) {
                ($guid,$slot,$attacker_team,$name) = ($1,$2,$3);
                print "BOMB: $name \[$attacker_team\] defused the bomb.\n";
            } else {
		print "WARNING: unrecognized A line format:\n\t$line\n";
	    }
	}
	elsif (($first_char eq chr(13)) || ($first_char eq '')) { 
	    # Empty Line
	} else { 
	    # WTF?!
	    print "WTF: $first_char and $line\n";
	}
	
    } else { 
	# We have reached the end of the logfile.  Timers for odd-jobs

	# Delay for a second so we aren't constantly hammering this loop
	if ($logfile_mode eq 'local') {
	    sleep 1;
	} elsif ($logfile_mode eq 'ftp') {
	    sleep $ftp_sleepInterval;
	}
	
	# Windows IO::File needs this to work correctly in perl2exe
	# It will never read new lines from the file until this
	#   error is manually cleared.
	#if ($logfile_mode eq 'local') {
	#    LOGFILE->clearerr();
	#}

	# cache the time to limit the number of syscalls
	$time = time;
	$timestring = scalar(localtime($time));
	
	# Freshen the rcon status if it's time
	if ( ($time - $last_rconstatus) >= $rconstatus_interval ) {
	    $last_rconstatus = $time;
	    &rcon_status();
	}
	
	# Anti-Idle check
	if ($config->{'antiidle'}) {
	    if ( ($time - $last_idlecheck) >= $idlecheck_interval ) {
		$last_idlecheck = $time;
		&idle_check();
	    }
	}

        # Check for bad names if its time
        if ( ($time - $last_namecheck) >= $namecheck_interval ) {
            $last_namecheck = $time;
            &check_player_names();
        }

        # Check if it is time to make our next announement yet.
        if ( $time >= $next_announcement ) {
            $next_announcement = $time + ( 60 * ( $config->{'interval_min'} + int( rand( $config->{'interval_max'} - $config->{'interval_min'} + 1 ) ) ) );
            &make_announcement();
        }

	# Check if it is time to make our next affiliate server announement yet.
	if ($config->{'affiliate_server_announcements'}) {
	    if ( $time >= $next_affiliate_announcement ) {
		$next_affiliate_announcement = $time + $config->{'affiliate_server_announcement_interval'};
		&make_affiliate_server_announcement();
	    }
	}

	# Check to see if its time to reactivate voting
	if (($reactivate_voting) && ($time >= $reactivate_voting)) {
	    $reactivate_voting = 0;
	    if ($voting) {
		&rcon_command("g_allowvote 1");
		# sleep 1;
		print "Reactivated voting...\n";
	    }
	}

	# Check to see if it's time to audit a GUID 0 person
	if (($config->{'audit_guid0_players'}) && ( ($time - $last_guid0_audit) >= $guid0_audit_interval )) {
            $last_guid0_audit = $time;
            &check_guid_zero_players();
        }

	# Check to see if we need to predict the next level
	if ($freshen_next_map_prediction) {
	    $temporary = &rcon_query('sv_mapRotationCurrent');
	    if ($temporary =~ /\"sv_mapRotationCurrent\" is: \"\s*gametype\s+(\w+)\s+map\s+(\w+)/m) {
		($next_gametype,$next_map) = ($1,$2);
		if (!defined($description{$next_gametype})) { $description{$next_gametype} = $next_gametype }
		if (!defined($description{$next_gametype})) { $description{$next_map} = $next_map }
		print "Next Map:  " . $description{$next_map} .  " - and Next Gametype: " .  $description{$next_gametype} . "\n"; 
		$freshen_next_map_prediction = 0;
		# MySQL Next Map Logging
		if ((defined($config->{'mysql_logging'})) && ($config->{'mysql_logging'})) {
		    $mysql_nextmap_sth = $mysql_logging_dbh->prepare("UPDATE next_map SET map = ?, gametype = ?");
		    $mysql_nextmap_sth->execute($description{$next_map}, $description{$next_gametype}) 
			or &mysql_fail("WARNING: Unable to do MySQL nextmap update\n");
		}
	    } else {
		$temporary = &rcon_query('sv_mapRotation');
		if ($temporary =~ /\"sv_mapRotation\" is: \"\s*gametype\s+(\w+)\s+map\s+(\w+)/m) {
		    ($next_gametype,$next_map) = ($1,$2);
		    if (!defined($description{$next_gametype})) { $description{$next_gametype} = $next_gametype }
		    if (!defined($description{$next_gametype})) { $description{$next_map} = $next_map }
		    print "Next Map:  " . $description{$next_map} .  " - and Next Gametype: " .  $description{$next_gametype} . "\n";
		    $freshen_next_map_prediction = 0;
                # MySQL Next Map Logging
		    if ((defined($config->{'mysql_logging'})) && ($config->{'mysql_logging'})) {
			$mysql_nextmap_sth = $mysql_logging_dbh->prepare("UPDATE next_map SET map = ?, gametype = ?");
			$mysql_nextmap_sth->execute($description{$next_map}, $description{$next_gametype})
			    or print "WARNING: Unable to do MySQL nextmap update\n";
		    }
		} else {
		    print "WARNING: unable to predict next map:  $temporary\n";
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
    if (!defined($config_file)) { 
	&die_nice("load_config_file() called without an argument\n");
    }
    if (!-e $config_file) { 
	&die_nice("load_config_file() config file does not exist: $config_file\n");
    }
    
    open (CONFIG, $config_file) ||
	&die_nice("$config_file file exists, but i couldnt open it.\n");
    
    my $line;
    my $config_name;
    my $config_val;
    my $command_name;
    my $temp;
    my $rule_name = 'undefined';
    my $response_count = 1;
    my $regex_match;
    my $location;

    print "\nParsing config file: $config_file...\n\n";
    
    while (defined($line = <CONFIG>)) {
	$line =~ s/\s+$//;
	if ($line =~ /^\s*(\w+)\s*=\s*(.*)/) {
	    ($config_name,$config_val) = ($1,$2);
	    if ($config_name eq 'ip_address') { 
		$config->{'ip'} = $config_val;
		if ($config_val eq 'localhost|loopback') {
		$config->{'ip'} = $localip; }
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
		} else {
		    print "WARNING: invalid synatx for location_spoofing:\n";
		    print "on line: $config_name = $config_val\n";
		    print "\n\tINVALID syntax.  Check config file\n";
		    print "\tUse the format:  location_spoofing = Name = Location\n";
		}
	    }
	    elsif ($config_name eq 'description') {
                if ($config_val =~ /(.*) = (.*)/) {
                    $description{$1} = $2;
                } else {
                    print "WARNING: invalid synatx for description:\n";
                    print "on line: $config_name = $config_val\n";
                    print "\n\tINVALID syntax.  Check config file\n";
                    print "\tUse the format:  description = term = Description\n";
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
		    if ($config_val =~ /disabled/i) { print "!$command_name command is DISABLED\n"; }
		    else { print "Allowing $config_val to use the $command_name command\n"; }
		} else {
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
		print "RCON pass: $config->{'rcon_pass'}\n";
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
                print "Anouncement: $config_val\n";
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
	    elsif ($config_name =~ /^(audit_guid0_players|antispam|antiidle|glitch_server_mode|ping_enforcement|999_quick_kick|flood_protection|killing_sprees|bullshit_calls|first_blood|anti_vote_rush|mysql_logging|ban_name_thieves|affiliate_server_announcements|use_passive_ftp|guid_sanity_check)$/) {
		if ($config_val =~ /yes|1|on|enable/i) { $config->{$config_name} = 1; }
                else { $config->{$config_name} = 0; }
                print "$config_name: " . $config->{$config_name} . "\n";
            }
	    elsif ($config_name =~ 'interval_m[ia][nx]|banned_name_warn_message_[12]|banned_name_kick_message|max_ping_average|glitch_kill_kick_message|anti(spam|idle)_warn_(level|message)_[12]|anti(spam|idle)_kick_(level|message)|ftp_(username|password|refresh_time)|mysql_(username|password|hostname|database)|affiliate_server_announcement_interval') {
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
    
    if (!defined($config->{'ip'})) { 
	&die_nice("Config File: ip_address is not defined\tCheck the config file: $config_file\n");
    }
    if (!defined($config->{'rcon_pass'})) { 
	&die_nice("Config File: rcon_pass is not defined\tCheck the config file: $config_file\n");
    }
    
    print "\nFinished parsing config: $config_file\n\n";

}
# END: load_config_file()

# BEGIN: die_nice(message)
sub die_nice {
    my $message = shift;
    if ((!defined($message)) || ($message !~ /./)) {
	$message = 'default die_nice message.\n\n';
    }
    
    print "\nCritical Error: $message\n\n";
    
  #  if ($^O eq 'MSWin32') {
	print "Press <ENTER> to skip this message and close this program\n"; 
	my $who_cares = <STDIN>;
  #  }
    -e $ftp_tmpFileName && unlink($ftp_tmpFileName);
    exit 1; }
# END: die_nice();


# BEGIN: open_server_logfile(logfile);
# this is an os-abstracted routine for opening the cod2 server logfile handle
sub open_server_logfile {
    my $log_file = shift;
    if (!defined($log_file)) { 
	&die_nice("open_server_logfile() called without an argument\n");
    }
    if (!-e $log_file) { 
	&die_nice("open_server_logfile() file does not exist: $log_file\n");
    }
    print "Opening $log_file for reading...\n\n"; 
    #if ($^O eq 'MSWin32') {
	#open (LOGFILE, "< :raw", $log_file) ||
	#   &die_nice("unable to :raw open $log_file: $!\n");
    #} else {
	open (LOGFILE, $log_file) ||
	    &die_nice("unable to open $log_file: $!\n");
    }
#}
# END: open_server_logfile();


# BEGIN: seek_to_end()
# This will move the pointer all the way to the end of the LOGFILE handle
sub seek_to_end {
    #if ($^O eq 'MSWin32') {
	# windows likes it in the 2nd to the last place.
	#seek(LOGFILE, -2, 2);
	
	# perl2exe needs help with filehandles.
	#LOGFILE->clearerr();
	
    #} else {
	seek(LOGFILE, 0, 2);
    }
#}
# END: seek_to_end()

# BEGIN: cache_guid_to_name(guid,name)
sub cache_guid_to_name {
    my $guid = shift;
    my $name = shift;
    
    # idiot gates
    if (!defined($guid)) { 
	&die_nice("cache_guid_to_name() was called without a guid number\n");
    } elsif ($guid !~ /^\d+$/) { 
	&die_nice("cache_guid_to_name() guid was not a number: |$guid|\n");
    } elsif (!defined($name)) {
	&die_nice("cache_guid_to_name() was called without a name\n");
    }
    
    if ($guid) {
	# only log this if the guid isn't zero
	my $sth = $guid_to_name_dbh->prepare("SELECT count(*) FROM guid_to_name WHERE guid=? AND name=?");
	$sth->execute($guid,$name) or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
	my @row = $sth->fetchrow_array;
	if ($row[0]) { }
	else { 
	    &log_to_file('logs/guid.log', "Caching GUID to NAME mapping: $guid - $name");
	    print "Caching GUID to NAME mapping: $guid - $name\n";
	    $sth = $guid_to_name_dbh->prepare("INSERT INTO guid_to_name VALUES (NULL, ?, ?)");
	    $sth->execute($guid, $name) or &die_nice("Unable to do insert\n");
	}
    }
}

# END: cache_guid_to_name()


# BEGIN: initialize_databases()
sub initialize_databases {
    my %tables;
    my $cmd;
    my $result_code;

    # populate the list of tables already in the databases.
    my $sth = $guid_to_name_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
    foreach ($sth->fetchrow_array) {
	$tables{$_} = $_;
    }
    
    # The GUID to NAME database
    if ($tables{'guid_to_name'}) { print "GUID <-> Name database brought online\n\n"; }
    else {
	print "Creating guid_to_name database\n\n";
	
	$cmd = "CREATE TABLE guid_to_name (id INTEGER PRIMARY KEY, guid INT(8), name VARCHAR(64) );";
	$result_code = $guid_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $guid_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code rows were inserted\n"; }
	
	$cmd = "CREATE INDEX guid_index ON guid_to_name (guid,name)";
	$result_code = $guid_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $guid_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code rows were inserted\n"; }
    }
        
    # The region code lookup table
    #$sth = $region_names_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    #$sth->execute or &die_nice("Unable to execute query: $region_names_dbh->errstr\n");
    #foreach ($sth->fetchrow_array) {
    #    $tables{$_} = $_;
    #}
    #if ($tables{'region_names'}) { print "Region Code <-> Region Name database brought online\n\n"; }
    #else {
	#&die_nice("ERROR: Region name database does not exist.\nPlease run make_region_names in the databases folder\n");
    #}	
    
    # The IP to GUID mapping table
    $sth = $ip_to_guid_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
    foreach ($sth->fetchrow_array) {
        $tables{$_} = $_;
    }
    if ($tables{'ip_to_guid'}) { print "IP <-> GUID database brought online\n\n"; }
    else {
	print "Creating ip_to_guid database\n\n";
	
	$cmd = "CREATE TABLE ip_to_guid (id INTEGER PRIMARY KEY, ip VARCHAR(15), guid INT(8) );";
	$result_code = $ip_to_guid_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_guid_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	
	$cmd = "CREATE INDEX ip_to_guid_index ON ip_to_guid (ip,guid)";
	$result_code = $ip_to_guid_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_guid_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
	
    }	
    
    # The IP to NAME mapping table
    $sth = $ip_to_name_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
    foreach ($sth->fetchrow_array) {
        $tables{$_} = $_;
    }
    if ($tables{'ip_to_name'}) { print "IP <-> NAME database brought online\n\n"; }
    else {
	print "Creating ip_to_name database\n\n";
	
	$cmd = "CREATE TABLE ip_to_name (id INTEGER PRIMARY KEY, ip VARCHAR(15), name VARCHAR(64) );";
	$result_code = $ip_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	
	$cmd = "CREATE INDEX ip_to_name_index ON ip_to_name (ip,name)";
	$result_code = $ip_to_name_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $ip_to_name_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
	
    }	
    
    # The !seen database
    $sth = $seen_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
    foreach ($sth->fetchrow_array) {
        $tables{$_} = $_;
    }
    if ($tables{'seen'}) { print "!seen database brought online\n\n"; }
    else {
	print "Creating seen database\n\n";
	
	$cmd = "CREATE TABLE seen (id INTEGER PRIMARY KEY, name VARCHAR(64), time INTEGER, saying VARCHAR(128) );";
	$result_code = $seen_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $seen_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	
	$cmd = "CREATE INDEX seen_time_saying ON seen (name,time,saying)";
	$result_code = $seen_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $seen_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
	
    }	
 
    # The !bans database
    $sth = $bans_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
    foreach ($sth->fetchrow_array) {
        $tables{$_} = $_;
    }

    if ($tables{'bans'}) { print "ban database brought online\n\n"; }
    else {
        print "Creating ban database\n\n";

        $cmd = "CREATE TABLE bans (id INTEGER PRIMARY KEY, ban_time INTEGER, unban_time INTEGER, ip VARCHAR(15), guid INTEGER, name VARCHAR(64) );";
        $result_code = $bans_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $bans_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code tables were created\n"; }

        $cmd = "CREATE INDEX bans_all ON bans (id, name, ban_time, unban_time, ip, guid, name)";
        $result_code = $bans_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $bans_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }

    # The definitions database
    $sth = $definitions_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $bans_dbh->errstr\n");
    my @tmp;
    while (@tmp = $sth->fetchrow_array) {
        foreach (@tmp) {
            $tables{$_} = $_;
        }
    }
    
    if ($tables{'definitions'}) { print "definitions database brought online\n\n"; }
    else {
        print "Creating definitions database\n\n";
	
        $cmd = "CREATE TABLE definitions (id INTEGER PRIMARY KEY, term VARCHAR(32), definition VARCHAR(250) );";
        $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	
        $cmd = "CREATE INDEX definitions_all ON definitions (id, term, definition)";
        $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }
    
    if ($tables{'cached'}) { print "cached definitions index database brought online\n\n"; }
    else {
        print "Creating cached database\n\n";

        $cmd = "CREATE TABLE cached (id INTEGER PRIMARY KEY, term VARCHAR(32));";
        $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code tables were created\n"; }

        $cmd = "CREATE INDEX cached_all ON cached (id, term)";
        $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }

    if ($tables{'cached_definitions'}) { print "cached definitions data database brought online\n\n"; }
    else {
        print "Creating cached_definitions database\n\n";

        $cmd = "CREATE TABLE cached_definitions (id INTEGER PRIMARY KEY, term VARCHAR(32), definition VARCHAR(250));";
        $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code tables were created\n"; }

        $cmd = "CREATE INDEX cached_defintions_all ON cached_definitions (id, term, definition)";
        $result_code = $definitions_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $definitions_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
    }

    # The !stats database
    $sth = $stats_dbh->prepare("SELECT name FROM SQLITE_MASTER");
    $sth->execute or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
    
    while (@tmp = $sth->fetchrow_array) {
	foreach (@tmp) {
	    $tables{$_} = $_;
	}
    }
    if ($tables{'stats'}) { print "!stats database brought online\n\n"; }
    else {
	print "Creating stats database\n\n";
	
	$cmd = "CREATE TABLE stats (id INTEGER PRIMARY KEY, name VARCHAR(64), kills INTEGER, deaths INTEGER, headshots INTEGER );";
	$result_code = $stats_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	
	$cmd = "CREATE INDEX stats_index ON stats (name,kills,deaths,headshots)";
	$result_code = $stats_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
	if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
	
    }
    if ($tables{'stats2'}) { print "The other !stats database brought online\n\n"; }
    else {
        print "Creating the other stats database\n\n";

        $cmd = "CREATE TABLE stats2 (id INTEGER PRIMARY KEY, name VARCHAR(64), pistol_kills INTEGER, grenade_kills INTEGER, bash_kills INTEGER, shotgun_kills INTEGER, sniper_kills INTEGER, rifle_kills INTEGER, machinegun_kills INTEGER, best_killspree INTEGER, nice_shots INTEGER, bullshit_shots INTEGER);";
        $result_code = $stats_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code tables were created\n"; }

        $cmd = "CREATE INDEX stats2_index ON stats2 (name,pistol_kills,grenade_kills,bash_kills,shotgun_kills,sniper_kills,rifle_kills,machinegun_kills,best_killspree,nice_shots,bullshit_shots)";
        $result_code = $stats_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $stats_dbh->errstr\n");
        if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }

    }

    # MySQL logging
    if ((defined($config->{'mysql_logging'})) && ($config->{'mysql_logging'})) {
	$mysql_logging_dbh = DBI->connect('dbi:mysql:' . $config->{'mysql_database'} . ':' . $config->{'mysql_hostname'}, 
					  $config->{'mysql_username'}, $config->{'mysql_password'})
	    or die "MYSQL LOGGING: Couldn't connect to mysql database: $DBI::errstr\n";
	
	print "MySQL Logging database brought online\n\n";

	$mysql_is_broken = 0;

	$sth = $mysql_logging_dbh->prepare("show tables");
	$sth->execute or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
	
	while (@tmp = $sth->fetchrow_array) {
	    foreach (@tmp) {
		$tables{$_} = $_;
	    }
	}
	if ($tables{'chat_log'}) { print "MySQL chat_log table already exists\n\n"; }
	else {
	    print "Creating chat_log table\n\n";
	    
	    $cmd = "CREATE TABLE chat_log (id INTEGER PRIMARY KEY AUTO_INCREMENT, name VARCHAR(64), timestamp INTEGER, message VARCHAR(250));";
	    $result_code = $mysql_logging_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $mysql_logging_dbh->errstr\n");
	    if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	    
	    $cmd = "CREATE INDEX chat_log_1 ON chat_log (id,name)";
	    $result_code = $mysql_logging_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $mysql_logging_dbh->errstr\n");
	    if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
	    
            $cmd = "CREATE INDEX chat_log_2 ON chat_log (id,timestamp)";
            $result_code = $mysql_logging_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $mysql_logging_dbh->errstr\n");
            if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }

	    $cmd = "CREATE INDEX chat_log_3 ON chat_log (id,message)";
            $result_code = $mysql_logging_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $mysql_logging_dbh->errstr\n");
            if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
	}


	if ($tables{'next_map'}) { print "MySQL next_map table already exists\n\n"; }
        else {
            print "Creating next_map table\n\n";

            $cmd = "CREATE TABLE next_map (map VARCHAR(250), gametype VARCHAR(250));";
            $result_code = $mysql_logging_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $mysql_logging_dbh->errstr\n");
            if (!$result_code) { print "ERROR: $result_code tables were created\n"; }
	    
            $cmd = "INSERT INTO next_map VALUES('Unknown', 'Unknown')";
            $result_code = $mysql_logging_dbh->do($cmd) or &die_nice("Unable to prepare execute $cmd: $mysql_logging_dbh->errstr\n");
            if (!$result_code) { print "ERROR: $result_code indexes were created\n"; }
	
	}


	
    }
    
    print "
=======================================
         CoD2 Server NannyBot
           version $version
            by smugllama
			
         for Call of Duty 2

    rcon code provided by KKrcon
  see: http://kkrcon.sourceforge.net

  IP Geolocation provided by MaxMind
     see: http://www.maxmind.com

   Support for remote FTP logfiles
  is based on ftptail by Will Moffat 
 see:  http://hamstersoup.com/ftpfail

 The Latest Version of Nannybot is at:
   http://smaert.com/nannybot.zip
   
         Перевод - VoroN
		 
=======================================
";


}
# END: initialize_databases()


# BEGIN: idle_check()
sub idle_check {
    my $slot;
    my $idle_for;
    print "Checking for idle players...\n";
    foreach $slot (keys %last_activity_by_slot) {
	if ($slot > 0) {
	    if (($slot != -1) && ($last_activity_by_slot{$slot} ne 'gone')) {
		$idle_for = $time - $last_activity_by_slot{$slot};

		if ($idle_for > 120) {
		    print "Slot $slot: $name_by_slot{$slot} has been idle for " . duration($idle_for) . "\n";
		}
		if (!defined($idle_warn_level{$slot})) { $idle_warn_level{$slot} = 0; }
                if (($idle_warn_level{$slot} < 1) && ($idle_for >= $config->{'antiidle_warn_level_1'})) {
                    print "IDLE_WARN1: Idle Time for $name_by_slot{$slot} has exceeded warn1 threshold: " . duration($config->{'antiidle_warn_level_1'}) . "\n";
                    &rcon_command("say $name_by_slot{$slot} ^7" . $config->{'antiidle_warn_message_1'} . '  (idle for ' . duration($idle_for) . ')');
                    # sleep 1;
                    $idle_warn_level{$slot} = 1;
                }
		if (($idle_warn_level{$slot} < 2) && ($idle_for >= $config->{'antiidle_warn_level_2'})) {
		    print "IDLE_WARN2: Idle Time for $name_by_slot{$slot} has exceeded warn2 threshold: " . duration($config->{'antiidle_warn_level_2'}) . "\n";
                    &rcon_command("say $name_by_slot{$slot} ^7" . $config->{'antiidle_warn_message_2'} . '  (idle for ' . duration($idle_for) . ')');
                    # sleep 1;
		    $idle_warn_level{$slot} = 2;
		}
		if ($idle_for >= $config->{'antiidle_kick_level'}) {
		    print "KICK: Idle Time for $name_by_slot{$slot} exceeded.\n";
		    &rcon_command("say $name_by_slot{$slot} ^7" . $config->{'antiidle_kick_message'});
                    sleep 1;
		    &rcon_command("say $name_by_slot{$slot}" . '" ^7был выкинут за то что был афк слишком долго: "' . duration($idle_for));
		    sleep 1;
		    &rcon_command("clientkick $slot");
		    # sleep 1;
		    &log_to_file('logs/kick.log', "IDLE: $name_by_slot{$slot} was kicked for being idle");
		}
	    }
	}
    }
}
# END: idle_check()


# BEGIN: chat()
sub chat{
    # Relevant Globals: 
    #   $name
    #   $slot 
    #   $message
    #   $guid

    if (!defined($ignore{$slot})) { $ignore{$slot} = 0; }
    # print "DEBUG: slot: $slot ignore: $ignore{$slot}\n"; 
    # print the message to the console
    if ($config->{'show_talk'}) {
	print &strip_color("CHAT: $name: $message\n");
    }
    
    &log_to_file('logs/chat.log', &strip_color("CHAT: $name: $message"));
    
    # MySQL Chat Logging
    my $sth;
    if ((defined($config->{'mysql_logging'})) && ($config->{'mysql_logging'})) {
	if (!$mysql_is_broken) {
	    $sth = $mysql_logging_dbh->prepare("INSERT INTO chat_log VALUES ('', ?, ?, ?)");
	    $sth->execute($name, $time, $message) or &mysql_fail("WARNING: Unable to do MySQL chat log insert\n");
	} else { &mysql_repair(); }
    }

    # Anti-Spam functions
    if ($config->{'antispam'}) {
	if (!defined($spam_last_said{$slot})) { $spam_last_said{$slot} = $message; }
	else {
	    if ($spam_last_said{$slot} eq $message) {
		if (!defined($spam_count{$slot})) { $spam_count{$slot} = 1; }
		else { $spam_count{$slot} += 1; }
		
		if ($spam_count{$slot} == $config->{'antispam_warn_level_1'}) {
		    &rcon_command("say $name_by_slot{$slot}: " . $config->{'antispam_warn_message_1'});
		    $penalty_points{$slot} += 10;
		    # sleep 1;
		}
		if ($spam_count{$slot} == $config->{'antispam_warn_level_2'}) {
                    &rcon_command("say $name_by_slot{$slot}: " . $config->{'antispam_warn_message_2'});
		    $penalty_points{$slot} += 20;
		    # sleep 1;
                }
		if (($spam_count{$slot} >= $config->{'antispam_kick_level'}) 
		    && ($spam_count{$slot} <= ( $config->{'antispam_kick_level'} + 1))) {
		    
		    if (&flood_protection('anti-spam-kick', 60, $slot)) { 
			# some douchebag flooded the engine.  (turning it off for a while.)
		    } else { 

			&rcon_command("say $name_by_slot{$slot}: " . $config->{'antispam_kick_message'});
			sleep 1;
			&rcon_command("clientkick $slot");
			# sleep 1;
			&log_to_file('logs/kick.log', "SPAM: $name_by_slot{$slot} was kicked for spamming: $message");
		    }
                }
		print "Spam:  $name said $message repeated $spam_count{$slot} times\n";
		
	    } else {
		$spam_last_said{$slot} = $message;
		$spam_count{$slot} = 0;
	    } 
	}
    }
    # End Anti-Spam functions
    
    
    # populate the !seen data
    my $is_there;
    $sth = $seen_dbh->prepare("SELECT count(*) FROM seen WHERE name=?");
    $sth->execute($name) or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
    foreach ($sth->fetchrow_array) {
	$is_there = $_;
    }
    if ($is_there) {
	# print "Updating Seen Data: $name - $time - $message\n";
	$sth = $seen_dbh->prepare("UPDATE seen SET time=?, saying=? WHERE name=?");
	$sth->execute($time,$message,$name) or &die_nice("Unable to do update\n");
	
    } else { 
	# print "Adding Seen Data: $name - $time - $message\n";
	$sth = $seen_dbh->prepare("INSERT INTO seen VALUES (NULL, ?, ?, ?)");
	$sth->execute($name,$time,$message) or &die_nice("Unable to do insert\n");
    }
    # end of !seen data population


    # ##################################
    # Server Response / Penalty System #
    # ##################################

    my $rule_name;
    my $penalty = 0;
    my $response = 'undefined';
    my $index;

    my $flooded = 0;

    # loop through all the rule regex looking for matches
    foreach $rule_name (keys %rule_regex) {
        if ($message =~ /$rule_regex{$rule_name}/i) {
            # We have a match, initiate response.

	    if (&flood_protection("chat-response-$rule_name", 60, $slot)) { $flooded = 1; }
	    else { $flooded = 0; }


            $index = $number_of_responses{$rule_name};
            if ($index) {
                $index = int(rand($index)) + 1;
                $response = $rule_response->{$rule_name}->{$index};
                $penalty = $rule_penalty{$rule_name};

		if ((!$flooded) && (!$ignore{$slot})) {
		 #   sleep 1; 
		    &rcon_command("say ^1$name:^7 $response");
		    &log_to_file('logs/response.log', "Rule: $rule_name  Match Text: $message");
		 #   sleep 1;
		}
            }
	    if ((!$flooded) && (!$ignore{$slot})) {
		print "Positive Match:\nRule Name: $rule_name\nPenalty: $penalty\nResponse: $response\n\n";
	    }

            if (!defined($penalty_points{$slot})) { $penalty_points{$slot} = $penalty; }
            else { $penalty_points{$slot} += $penalty; }

            print "Penalty Points total for: $name:  $penalty_points{$slot}\n";

            if ($penalty_points{$slot} >= 100) {
                &rcon_command("say ^1$name:^2 " . '"Я думаю мы услышали достаточно, убирайся отсюда!"');
                sleep 1;
                &rcon_command("clientkick $slot");
                &log_to_file('logs/kick.log', "PENALTY: $name was kicked for exceeding their penalty points.  Last Message: $message");
            }
        }
    }
    #  End of Server Response / Penalty System

    # Call Bullshit
    if (($config->{'bullshit_calls'}) && (!$ignore{$slot})) {
	if ($message =~ /^!?bs\W*$|^!?bull\s*shit\W*$|^!?hacks?\W*$|^!?hacker\W*$|^!?hax\W*$|^that was (bs|bullshit)\W*$/i) {
	    if ((defined($last_killed_by{$slot})) && (&strip_color($last_killed_by{$slot}) ne $name)) {
		if (&flood_protection('bullshit', 90, $slot)) {
		    # bullshit abuse
		    if (&flood_protection('bullshit-two', 30, $slot)) { }
		    else {
			&rcon_command("say ^2$name ^7is being a ^1WHINEY BITCH.");
			# sleep 1;
			$stats_sth = $stats_dbh->prepare("UPDATE stats2 SET bullshit_shots = bullshit_shots + 1 WHERE name=?");
			$stats_sth->execute($name) or &die_nice("Unable to update stats2\n");
			$penalty_points{$slot} += 12;
		    }
		}
		else {
		    # update the bullshit counter.
		    $stats_sth = $stats_dbh->prepare("UPDATE stats2 SET bullshit_shots = bullshit_shots + 1 WHERE name=?");
		    $stats_sth->execute(&strip_color( $last_killed_by{$slot})) or &die_nice("Unable to update stats2\n");
		    
		    &rcon_command("say ^2$name ^7called ^1BULLSHIT ^7on^2 $last_killed_by{$slot}");
		    # sleep 1;
		    $penalty_points{$slot} += 1;
		}
	    }  
	} 
    }
    # End of Bullshit

    # Call Nice Shot
    if ($message =~ /\bnice\W? (one|shot|1)\b|^n[1s]\W*$|^n[1s],/i) {
	print "NICE SHOT: " . &strip_color($last_killed_by{$slot}) . "\n"; 
    }
    # End Nice Shot


    # Auto-define questions (my most successful if statement evar?)
    if ((!$ignore{$slot}) && ($message =~ /(.*)\?$/) || ($message =~ /^!(.*)/)){
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
	    push @results, "$name: ^1$question ^3is:^2 $row[0]";
	}
    	
	if ($#results != -1) {
	    if (&flood_protection('auto-define', 60, $slot)) { }
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
	if ($message =~ /^!(locate|stalk)\s+(.+)/i) {
	    if (&check_access('locate')) {
		&locate($2);
	    }
	}
	elsif ($message =~ /^!locate\s*$/i) {
	    if (&check_access('locate')) {
		if (&flood_protection('locate-miss', 60, $slot)) { }
                else {
		    &rcon_command("say " . '"!locate кого?"');
		}
	    }
	}
	
        # !ignore (search_string)
        if ($message =~ /^!ignore\s+(.+)/i) {
            if (&check_access('ignore')) {
                &ignore($1);
            }
        }
        elsif ($message =~ /^!ignore\s*$/i) {
            if (&check_access('ignore')) {
                if (&flood_protection('ignore', 60, $slot)) { }
                else {
                    &rcon_command("say " . '"!ignore кого?"');
                }
            }
        }

        # !forgive (search_string)
        if ($message =~ /^!forgive\s+(.+)/i) {
            if (&check_access('forgive')) {
                &forgive($1);
            }
        }
        elsif ($message =~ /^!forgive\s*$/i) {
            if (&check_access('forgive')) {
                if (&flood_protection('forgive', 60, $slot)) { }
                else {
                    &rcon_command("say " . '"!forgive кого?"');
                }
            }
        }

	# !seen (search_string)
	elsif ($message =~ /^!seen\s+(.+)/i) { 
	    if (&check_access('seen')) {
		&seen($1);
	    }
	}
	elsif ($message =~ /^!seen\s*$/i) {
	    if (&check_access('seen')) {
		# sleep 1;
		if (&flood_protection('seen-miss', 60, $slot)) { }
		else {
		    &rcon_command("say " . '"!seen кого?"');
		}
	    }
	}

	# !kick (search_string)
	elsif ($message =~ /^!kick\s+(.+)/i) {
	    if (&check_access('kick')) {
		&kick_command($1);
	    } else {
		&rcon_command("clientkick $slot");
		&log_to_file('logs/kick.log', "ACCESS_DENIED: $name was kicked for trying to !kick others without access");
	    }
	}
	elsif ($message =~ /^!kick\s*$/i) {
	    if (&check_access('kick')) {
		&rcon_command("say " . '"!kick кого?"');
	    }
	}
	
	
	# !tempban (search_string)
	elsif ($message =~ /^!tempban\s+(.+)/i) {
	    if (&check_access('tempban')) {
		&tempban_command($1);
	    } else {
		&rcon_command("clientkick $slot");
		&log_to_file('logs/kick.log', "ACCESS_DENIED: $name was kicked for trying to !tempban others without access");
	    }
	}
	elsif ($message =~ /^!tempban\s*$/i) {
	    if (&check_access('tempban')) {
		&rcon_command("say " . '"!tempban кого?"');
	    }
	}
	
	# !ban (search_string)
	elsif ($message =~ /^!ban\s+(.+)/i) {
	    if (&check_access('ban')) {
		&ban_command($1);
	    } else {
		&rcon_command("clientkick $slot");
		&log_to_file('logs/kick.log', "ACCESS_DENIED: $name was kicked for trying to !ban others without access");
	    }
	}
	elsif ($message =~ /^!ban\s*$/i) {
	    if (&check_access('ban')) {
		&rcon_command("say " . '"!ban кого?"');
	    }
	}


        # !unban (search_string)
        elsif ($message =~ /^!unban\s+(.+)/i) {
            if (&check_access('ban')) {
                &unban_command($1);
            } else {
            }
        }
        elsif ($message =~ /^!unban\s*$/i) {
            if (&check_access('ban')) {
                &rcon_command("say " . '"Снять бан можно при помощи BAN ID,проверьте !lastbans чтобы узнать ID игроков которые были забанены"');
            }
        }
		
		# !deletestats (search_string)
        elsif ($message =~ /^!deletestats|clearstats\s+(.+)/i) {
            if (&check_access('clear_stats')) {
                &clear_stats($1);
            } else {
            }
        }
        elsif ($message =~ /^!deletestats|clearstats\s*$/i) {
            if (&check_access('clear_stats')) {
                &rcon_command("say " . '"!удалить статистику для кого?"');
            }
        }
	
       # !define (word)
        elsif ($message =~ /^!(define|dictionary|dict|словарь)\s+(.+)/i) {
            if (&check_access('define')) {
		if (&flood_protection('dictionary', 60 * 10, $slot)) { }
		else {
		    &dictionary($2);
		}
            }
        } elsif ($message =~ /^!(define|dictionary|dict|словарь)\s*$/i) {
            if (&check_access('define')) {
		if (&flood_protection('dictionary-miss', 60 * 10 ,$slot)) { }
		else {
		    &rcon_command("say $name_by_slot{$slot}^7, " . '"Что нужно добавить в ^5словарь?"');
		}
	    }
        }

	# !undefine (word)
        elsif ($message =~ /^!undefine\s+(.+)/i) {
	    my $undefine = $1;
	    my @row;
            if (&check_access('add-definition')) {
		$sth = $definitions_dbh->prepare('SELECT count(*) FROM definitions WHERE term=?;');
		$sth->execute($undefine) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
		@row = $sth->fetchrow_array();

		$sth = $definitions_dbh->prepare('DELETE FROM definitions WHERE term=?;');
		$sth->execute($undefine) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
		if ($row[0] == 1) {
		    &rcon_command("say " . '"^2Удалено определение для: "' . "^1 $undefine");
		} elsif ($row[0] > 1) {
		    &rcon_command("say " . '"^2Удалено "' . "$row[0]" . '" определений для: "' . "^1 $undefine");
		} else {
		    &rcon_command("say " . '"^2Больше нет определений для: "' . "^1 $undefine");
		}
		# we don't delete the online cache - even if somebody undefines it.
		# $sth = $definitions_dbh->prepare('DELETE FROM cached WHERE term=?;');
                # $sth->execute($undefine) or &die_nice("Unable to execute query: $definitions_dbh->errstr\n");
            }
        } 


        # !purge (#playerid)
#        elsif ($message =~ /^!purge\s+(\d+)/i) {
#            my $purge = $1;
#            my @row;
#            if (&check_access('purge')) {
#                $sth = $stats_dbh->prepare('SELECT count(*) FROM stats WHERE id=?;');
#                $sth->execute($purge) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
#                @row = $sth->fetchrow_array();
#
#                $sth = $definitions_dbh->prepare('DELETE FROM stats WHERE id=?;');
#                $sth->execute($purge) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
#                if ($row[0] == 1) {
#                    &rcon_command("say ^2Deleted the definition for: ^1 $undefine");
#                } elsif ($row[0] > 1) {
#                    &rcon_command("say ^2Deleted $row[0] definitions for: ^1 $undefine");
#                } else {
#                    &rcon_command("say ^2hey dip-shit, there are no definitions for: ^1 $undefine");
#                }
#            }
#        }

	# !stats - B
	elsif ($message =~ /^!stats\s*(.*)/i) {
	    my $stats_search = $1;
	    if (!defined($stats_search)) { $stats_search = ''; }
	    if (&check_access('stats')) {
		if (&check_access('peek')) {
		    &stats($name,$stats_search);
		} else {
		    &stats($name,'');
		}
	    }
	}
	
	# !awards
	elsif ($message =~ /^!(awards|top)\b/i) {
	    if (&check_access('awards')) {
		&awards();
	    }
	}
	# !suk
        elsif ($message =~ /^!(suk|deaths)\b/i) {
            if (&check_access('suk')) {
                &suk();
            }
        }
		
			# !rank
        elsif ($message =~ /^!(rnk)\b/i) {
           if (&check_access('rank')) {
                &rank();
				
            }
        }
	# !tdm
	elsif ($message =~ /^!tdm\b/i) {
	    if (&check_access('map_control')) {
		&change_gametype('tdm');
	    }
	}
	# !ctf
	elsif ($message =~ /^!ctf\b/i) {
	    if (&check_access('map_control')) {
		&change_gametype('ctf');
	    }
	}
	# !dm
	elsif ($message =~ /^!dm\b/i) {
	    if (&check_access('map_control')) {
		&change_gametype('dm');
	    }
	}
	# !hq
	elsif ($message =~ /^!hq\b/i) {
	    if (&check_access('map_control')) {
		&change_gametype('hq');
	    }
	}
	# !sd
	elsif ($message =~ /^!sd\b/i) {
	    if (&check_access('map_control')) {
		&change_gametype('sd');
	    }
	}

	# !teamkill  (moved to the !firendly fire command)
	# // scr_friendlyfire "0"   (Turns off team damage)
	# // scr_friendlyfire "1"   (Turns on team damage)
        # // scr_friendlyfire "2"   (Turns on reflective damage)
        # // scr_friendlyfire "3"   (Turns on shared damage)
        #elsif ($message =~ /^!(teamkill|team_kill|team kill)\s+(.+)/i) {
        #     if (&check_access('teamkill')) {
	#	&toggle_weapon('scr_friendlyfire', 'Friendly Fire', $2);
        #    }
        #}
        #elsif ($message =~ /^!(teamkill|team_kill|team kill)\s*$/i) {
        #    if (&check_access('teamkill')) {
        #        &rcon_command("say ^1$name: ^7You can turn^1 !$1 ^5on ^7or turn ^1 !$1 ^5off^7.  Which is it?");
        #    }
        #}

	# !smoke
        elsif ($message =~ /^!(smokes?|smoke_grenades?|smoke_nades?)\s+(.+)/i) {
	    if (&check_access('weapon_control')) {
		&toggle_weapon('scr_allow_smokegrenades', 'Smoke Grenades', $2);
	    }
	}
	elsif ($message =~ /^!(smokes?|smoke_grenades?|smoke_nades?)\s*$/i) {
	    if (&check_access('weapon_control')) {
		&rcon_command("say ^1$name: ^7You can turn^1 !$1 ^5on ^7or turn ^1 !$1 ^5off^7.  Which is it?");
	    }
	}

        # !grenades
        elsif ($message =~ /^!(nades?|grenades?|frag_grenades?|frag_nades?)\s+(.+)/i) {
            if (&check_access('weapon_control')) {
                &toggle_weapon('scr_allow_fraggrenades', 'Frag Grenades', $2);
            }
        }
        elsif ($message =~ /^!(nades?|grenades?|frag_grenades?|frag_nades?)\s*$/i) {
            if (&check_access('weapon_control')) {
                &rcon_command("say ^1$name: ^7You can turn^1 !$1 ^5on ^7or turn ^1 !$1 ^5off^7.  Which is it?");
            }
        }

        # !shotguns
        elsif ($message =~ /^!(shotguns?|trenchguns?|shot_guns?|trench_guns?)\s+(.+)/i) {
            if (&check_access('weapon_control')) {
                &toggle_weapon('scr_allow_shotgun', 'Shotguns', $2);
            }
        }
        elsif ($message =~ /^!(shotguns?|trenchguns?|shot_guns?|trench_guns?)\s*$/i) {
            if (&check_access('weapon_control')) {
                &rcon_command("say ^1$name: ^7You can turn^1 !$1 ^5on ^7or turn ^1 !$1 ^5off^7.  Which is it?");
            }
        }

	
	# !say
        elsif ($message =~ /^!say\s+(.+)/i) {
            if (&check_access('say')) {
                &rcon_command("say $1");
            }
        }

	# !broadcast
        elsif ($message =~ /^!broadcast\s+(.+)/i) {
            if (&check_access('broadcast')) {
                &broadcast_message($1);
            }
        }

        # !tell
        elsif ($message =~ /^!tell\s+([^\s]+)\s+(.*)/i) {
            if (&check_access('tell')) {
                &tell($1,$2);
            }
        }

	# !hostname and !servername
        elsif ($message =~ /^!(host ?name|server ?name)\s+(.+)/i) {
            if (&check_access('hostname')) {
		$server_name = $2;
                &rcon_command("sv_hostname $server_name");
				&rcon_command("say " . '"Изменяю название сервера..."' . "");
		sleep 1;
		&rcon_command("say ^2OK. " . '"^7Название сервера изменено на: "' . "$server_name");
		#sleep 1;
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
		    $ip_by_slot{$reset_slot} = 'SLOT_EMPTY';
		    $guid_by_slot{$reset_slot} = 0;
		    $spam_count{$reset_slot} = 0;
		    $last_ping{$reset_slot} = 0;
		    $ping_average{$reset_slot} = 0;
		    $penalty_points{$reset_slot} = 0;
		    $last_killed_by{$reset_slot} = '... ummm .... Sorry, I forgot.';
		    $kill_spree{$reset_slot} = 0;
		    $best_spree{$reset_slot} = 0;
		    $ignore{$reset_slot} = 0;
		}
		&rcon_command("say " . '"Хорошо "' . "$name^7," . '" перезапускаю себя..."');
		#sleep 1;
	    }
	}


	# !fixaliases
        elsif ($message =~ /^!(fixaliases|fixnames)/i) {
            my @row;
            if (&check_access('fixaliases')) {
                $sth = $guid_to_name_dbh->prepare('SELECT count(*) FROM guid_to_name;');
                $sth->execute() or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
                @row = $sth->fetchrow_array();

                $sth = $guid_to_name_dbh->prepare('DELETE FROM guid_to_name;');
                $sth->execute() or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
                if ($row[0] == 1) {
                    &rcon_command("say ^2Deleted the only record for GUID <-> NAME");
                } elsif ($row[0] > 1) {
                    &rcon_command("say ^2Deleted $row[0] GUID <-> NAME records");
                } else {
                    &rcon_command("say ^2hey dip-shit, there are no aliases to purge");
                }

                $sth = $ip_to_name_dbh->prepare('SELECT count(*) FROM ip_to_name WHERE length(name) > 31;');
                $sth->execute() or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
                @row = $sth->fetchrow_array();

                $sth = $ip_to_name_dbh->prepare('DELETE FROM ip_to_name WHERE length(name) > 31;');
                $sth->execute() or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
                if ($row[0] == 1) {
                    &rcon_command("say ^2Deleted the only record for IP <-> NAME");
                } elsif ($row[0] > 1) {
                    &rcon_command("say ^2Deleted $row[0] IP <-> NAME records that were too long");
                }
            }
        }



	# !version
	elsif ($message =~ /^!version\b/i) {
	    if (&check_access('version')) {
		if (&flood_protection('version', 120, $slot)) { }
		else {
		    &rcon_command("say NannyBot^7 for CoD2 version^2 $version ^7by ^4smugllama ^7/ ^1indie cypherable ^7/ Dick Cheney");
		    sleep 1;
		    &rcon_command("say ... with additional help from: Bulli, Badrobot, and Grisu Drache - thanks!");
		    sleep 1;
			&rcon_command("say " . '"^3Downloadable at:^2 http://smaert.com/nannybot.zip"');
			sleep 1;
			&rcon_command("say " . '"Русская версия от ^5V^0oro^5N"');
		    sleep 1;
		    &rcon_command("say " . '"^3Программу и исходный код данной русской версии можно найти тут:^2 https://github.com/alexey12424323/Nanny"');
		}	    
	    }
	}

        # !nextmap  (not to be confused with !rotate)
        elsif ($message =~ /^!(nextmap|next|nextlevel|next_map|next_level)\b/i) {
            if (&check_access('nextmap')) {
		if (&flood_protection('nextmap', 120, $slot)) { }
		else {
		    &rcon_command("say " . " ^2$name^7" . '": Следующая карта будет: ^1"' . $description{$next_map} .  " ^7(^2" .  
				  $description{$next_gametype} . "^7)");
		    #sleep 1;
		}
            }
        }

	# !rotate
	elsif ($message =~ /^!rotate\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Смена карты..."');
		sleep 1;
		&rcon_command('map_rotate');
	    }
	}
	# !restart
	elsif ($message =~ /^!restart\b/i) {
	    if (&check_access('map_control')) {
		&rcon_command("say " . '"^2Перезагрузка карты..."');
		sleep 1;
		&rcon_command('map_restart');
	    }
	}
	# !voting
	elsif ($message =~ /^!(voting|vote|allowvote|allowvoting)\s+(.+)/i) {
	    if (&check_access('voting')) {
		&voting_command($2);
	    }
	}
	elsif ($message =~ /^!(voting|vote|allowvote|allowvoting)\s*$/i) {
	    if (&check_access('voting')) {
		&rcon_command("say !voting on ... or !voting off ... ?");
	    }
	}
	
	# !killcam
	elsif ($message =~ /^!killcam\s+(.+)/i) {
	    if (&check_access('killcam')) {
		&killcam_command($1);
	    }
	}
	elsif ($message =~ /^!killcam\s*$/i) {
	    if (&check_access('killcam')) {
		&rcon_command("say  " . '"!killcam on  ... или !killcam off ... ?"');
	    }
	}
	
        # !friendlyfire
	# teamkill|team_kill|team kill
        elsif ( ($message =~ /^!fr[ie]{1,2}ndly.?fire\s+(.+)/i) ||
		($message =~ /^!team[ _\-]?kill\s+(.+)/i) ) {
            if (&check_access('friendlyfire')) {
                &friendlyfire_command($1);
            }
        }
        elsif ( ($message =~ /^!fr[ie]{1,2}ndly.?fire\s*$/i) ||
	       ($message =~ /^!team[ _\-]?kill\s*$/i) ) {
	    
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
		if ($state_string ne 'unknown') {
		    &rcon_command("say ^1$name: ^7 $state_string");
		}
            }
        }

	# !glitch
	elsif ($message =~ /^!glitch\s+(.+)/i) {
	    if (&check_access('glitch')) {
		&glitch_command($1);
	    }
	}
	elsif ($message =~ /^!glitch\s*$/i) {
	    if (&check_access('glitch')) {
		&rcon_command("say !glitch on" . '" или !glitch off ... ?"');
	    }
	}
	# forcerespawn
		elsif ($message =~ /^!forcerespawn\s*$/i) {
	    if (&check_access('forcerespawn')) {
		&rcon_command("say !forcerespawn on" . '" или !forcerespawn off?"');
	    }
	}
	# teambalance
		elsif ($message =~ /^!teambalance\s*$/i) {
	    if (&check_access('teambalance')) {
		&rcon_command("say !teambalance on" . '" или !teambalance off?"');
	    }
	}
	# spectatefree
		elsif ($message =~ /^!spectatefree\s*$/i) {
	    if (&check_access('spectatefree')) {
		&rcon_command("say !spectatefree on" . '" или !spectatefree off?"');
	    }
	}

	
        # !aliases (search_string)
        elsif ($message =~ /^!names\s+(.+)/i) {
            if (&check_access('aliases')) {
                &aliases($1);
            }
        }
        elsif ($message =~ /^!(names)\s*$/i) {
            if (&check_access('aliases')) {
                &rcon_command("say " . '"!names для кого?"');
            }
        }

        # !uptime
        elsif ($message =~ /^!uptime\b/i) {
            if (&check_access('uptime')) {
		if (&flood_protection('uptime', 120, $slot)) { }
		else {
		    if ($uptime =~ /(\d+):(\d+)/) {
			my $duration = &duration( ( $1 * 60 ) + $2 );
			&rcon_command("say " . '"Этот сервер запущен и работает уже"' . "$duration");
		    }
		}
	    }
        }


	# !help
	elsif ($message =~ /^!help|^!помощь\b/i) {
	    if (&flood_protection('help', 120, $slot)) {}
	    else {
		if (&check_access('stats')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!stats ^7чтобы узнать свою подробую статистику"');
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
		if (&check_access('aliases')) {
		    &rcon_command("say " . '"^7Вы можете ^1!names ^5игрок ^7чтобы узнать с какими никами он играл"');
		    sleep 1;
		}
		if (&check_access('awards')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!top ^7чтобы посмотреть список лучших десяти игроков на сервере"');
		    sleep 1;
		}
		if (&check_access('suk')) {
		    &rcon_command("say " . '"^7Вы можете использовать ^1!deaths ^7чтобы посмотреть список лучших десяти игроков по количеству смертей"');
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
                    &rcon_command("say " . '"^7Вы можете использовать  ^1!reset ^7чтобы перезапустить программу"');
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
		if (&flood_protection('fly', 300, $slot)) { }
		elsif (&flood_protection('fly', 60)) { }
		else {
		    &rcon_command("say " . '"Летите как птицы!!!"');
		    &rcon_command("g_gravity 15");
		    sleep 20;
		    # &rcon_command("g_gravity 60");
		    # &rcon_command("g_gravity 15");
		    # sleep 5;
		    &rcon_command("g_gravity 800");
		    # sleep 1;
		    &rcon_command("say " . '"Думаю стоит продолжить нормальную игру"');
		}
	    }
	}

        # !gravity (number)
        if ($message =~ /^!(g_gravity|gravity)\s*(.*)/i) {
            if (&check_access('gravity')) {
                &gravity_command($2);
            }
        }



        # !calc (expression)
        if ($message =~ /^!(calculater?|calc|calculator)\s+(.+)/i) {
	    my $expression = $2;
	    if  ($expression =~ /[^\d\.\+\-\/\* \(\)]/) {}
	    else { 
		&rcon_command("say ^2$expression ^7=^1 " . eval($expression) );
		# sleep 1;
	    }
        }
        # !speed (number)
        if ($message =~ /^!(g_speed|speed)\s*(.*)/i) {
            if (&check_access('speed')) {
                &speed_command($2);
            }
        }

	# !big red button
	if ($message =~ /^!(big red button|nuke)/i) {
	    if (&check_access('nuke')) {
		&big_red_button_command();
	    }
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
	
	# !el-alamein !egypt  
	elsif ($message =~ /^!(el.?alamein|egypt)\b/i) {
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
		&rcon_command("say " . '"^2Смена на: "' . "^3Caen France      ^7(mp_trainstation)");
		sleep 1;
		&rcon_command('map mp_trainstation');
	    }
	}
	# End of map !commands

	        elsif ($message =~ /^!time\b/i) {
            if (&check_access('time')) {
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
            $year = $year + 1900;
            $mon += 1;
			&rcon_command("say " . '"^2Московское время^7:^3"' . "$hour:$min");
            # sleep 1;
            }
        }
		
			elsif ($message =~ /^!date\b/i) {
            if (&check_access('time')) {
            ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
            $year = $year + 1900;
            $mon += 1;
            &rcon_command("say " . '"^2Текущая дата^7:^3"' . "$mday/$mon/$year");
            # sleep 1;
            }
        }

	        elsif ($message =~ /^!guid\b/i) {
            {
                &rcon_command("say " . " $name_by_slot{$slot}^7:" . '" ^7Твой ^1GUID^7 - ^2 "' . "$guid");
                # sleep 1;
            }
        }
		
			elsif ($message =~ /^!id\b/i) {
            {
                &rcon_command("say " . " $name_by_slot{$slot}^7:" . '" ^7Твой ^1ID^7 - ^2 "' . "$slot");
                # sleep 1;
            }
        }
		
			elsif ($message =~ /^!ip\b/i) {
            {
                &rcon_command("say " . " $name_by_slot{$slot}^7:" . '" ^7Твой ^1IP Адрес^7 - ^2 "' . "$ip_by_slot{$slot}");
                # sleep 1;
            }
        }
		
		    # bash mode only works when bash mod is installed
			elsif ($message =~ /^!bash on\b/i) {
			
			if (&check_access('bash_mode'))
            {
                &rcon_command("set bash_mode 1");
                # sleep 1;
            }
        }
		
			elsif ($message =~ /^!bash off\b/i) {
			
			if (&check_access('bash_mode'))
            {
                &rcon_command("set bash_mode 0");
                # sleep 1;
            }
        }
		
	 # !forcerespawn command
			elsif ($message =~ /^!forcerespawn on\b/i) {
			
			if (&check_access('forcerespawn'))
            {
                &rcon_command("scr_forcerespawn 1");
				&rcon_command("say " . '"Быстрое возрождение ^2Включено"');
                # sleep 1;
            }
        }
		
			elsif ($message =~ /^!forcerespawn off\b/i) {
			
			if (&check_access('forcerespawn'))
            {
                &rcon_command("scr_forcerespawn 0");
				&rcon_command("say " . '"Быстрое возрождение ^1Выключено"');
                # sleep 1;
            }
        }
	 # !teambalance command
			elsif ($message =~ /^!teambalance on\b/i) {
			
			if (&check_access('teambalance'))
            {
                &rcon_command("scr_teambalance 1");
				&rcon_command("say " . '"Автобаланс команд ^2Включен"');
                # sleep 1;
            }
        }
		
			elsif ($message =~ /^!teambalance off\b/i) {
			
			if (&check_access('teambalance'))
            {
                &rcon_command("scr_teambalance 0");
				&rcon_command("say " . '"Автобаланс команд ^1Выключен"');
                # sleep 1;
            }
        }
	 # !spectatefree command
			elsif ($message =~ /^!spectatefree on\b/i) {
			
			if (&check_access('spectatefree'))
            {
                &rcon_command("scr_spectatefree 1");
				&rcon_command("say " . '"Свободный режим наблюдения ^2Включен"');
                # sleep 1;
            }
        }
		
			elsif ($message =~ /^!spectatefree off\b/i) {
			
			if (&check_access('spectatefree'))
            {
                &rcon_command("scr_spectatefree 0");
				&rcon_command("say " . '"Свободный режим наблюдения ^1Выключен"');
                # sleep 1;
            }
        }

	# !lastbans N
	elsif ($message =~ /^!(lastbans?|recentbans?|bans|banned)\s+(\d+)/i) {
            if (&check_access('lastbans')) {
                &last_bans($2);
            }
        } elsif ($message =~ /^!(lastbans?|recentbans?|bans|banned)/i) {
            if (&check_access('lastbans')) {
                &last_bans(10);
            }
        }


	# !assrape  (shh.)
	elsif ($message =~ /^!(assrape|bitchslap|slap|cornhole|daterape|hatefuck|hate-fuck|rape|fuck)\s+(.+)/i) {
	    if (&check_access('assrape')) {
		&assrape($2);
            }
	}

	# !lastkill
        elsif ($message =~ /^!(last\s*kill|killedby|whokilledme|whowasthat)\s*(.*)/i) {
	    my $lastkill_search = $2;
	    if ((!defined($lastkill_search)) || ($lastkill_search eq '')) { $lastkill_search = ''; }
            if (&check_access('lastkill')) {
		print "DEBUG: slot = $slot  and last killed by = $last_killed_by{$slot}\n";
		if (&flood_protection('lastkill', 60, $slot)) { }
		else {
		    if (($lastkill_search ne '') && (&check_access('peek'))) {
			
			my @matches = &matching_users($lastkill_search);
			if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . "$lastkill_search"); }
			elsif ($#matches == 0) {
			    if ((defined( $last_killed_by{$matches[0]} )) && ($last_killed_by{$matches[0]} ne '... ummm .... Sorry, I forgot.')) {
				&rcon_command("say ^2" . $name_by_slot{$matches[0]} . '"^3 ^7был убит игроком ^1"' . $last_killed_by{$matches[0]} );
			    } else {
				&rcon_command("say ^2$name^3:" . '"^7К сожалению, не удалось найти результат..."');
			    }

			}
			elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много данных на: "' . "$lastkill_search"); }
		    } else {
			if ((defined( $last_killed_by{$slot} )) && ($last_killed_by{$slot} ne '... ummm .... Sorry, I forgot.')) {
			    &rcon_command("say ^2$name^3:" . '"^7Вы были убиты игроком ^1"' . $last_killed_by{$slot} );
			} else { 
			    &rcon_command("say ^2$name^3:" . '"^7К сожалению, не удалось найти результат..."');
			}
		    }
		    # sleep 1;
		    
		}
            }
        }


#   !stats duplicate - a template. - thanks, Laz
#        elsif ($message =~ /^!stats\s*(.*)/i) {
#            my $stats_search = $1;
#            if (!defined($stats_search)) { $stats_search = ''; }
#            if (&check_access('stats')) {
#                if (&check_access('peek')) {
#                    &stats($name,$stats_search);
#                } else {
#                    &stats($name,'');
#                }
#            }
#        }
    }
    # END of  !commands 
}
# END: chat()



# BEGIN: strip_color($string)
sub strip_color {
    my $string = shift;
    $string =~ s/\^\d//g;
    return $string;
}
# END: strip_color()


# BEGIN: locate($search_string)
sub locate {
    my $search_string = shift;
    my $key;
    my $location;
    my @matches = &matching_users($search_string);
    my $ip;
    my $guessed;
    my $spoof_match;
    if (($search_string =~ /^\.$|^\*$|^all$|^.$/i) && (&flood_protection('locate-all', 300))) { return 1; }
    if (&flood_protection('locate', 60, $slot)) { return 1; }
    foreach $key (@matches) {
	if ((&strip_color($name_by_slot{$key}))) {
	    print "MATCH: $name_by_slot{$key}   IP = $ip_by_slot{$key}\n";
	    $ip = $ip_by_slot{$key};
	    if ($ip =~ /\?$/) {
		$guessed = 1;
		$ip =~ s/\?$//;
	    }
	    if ($ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/) { 
		$location = &geolocate_ip_win32($ip);
		if ($location =~ /,.* - .+/) {
		    if ($guessed) { $location = $name_by_slot{$key} . '"^7 вероятно зашел к нам из районов около ^2"' . $location; }
		    else { $location = $name_by_slot{$key} . '"^7 зашел к нам из^2"' . $location; }
		} else {
		    if ($guessed) { $location = $name_by_slot{$key} . '"^7 вероятно зашел к нам из ^2"' . $location; }
		    else { $location = $name_by_slot{$key} . '"^7 зашел к нам из ^2"' . $location; }
		}

		# location spoofing
		foreach $spoof_match (keys(%location_spoof)) {
		    if ($name_by_slot{$key} =~ /$spoof_match/i) {
			$location = $name_by_slot{$key} . '^7 ' . $location_spoof{$spoof_match};
		    }
		}

		&rcon_command("say ^5#$key^7: $location");
		print "$location\n"; 
		#sleep 1;
	    } else {
		# no valid IP for this slot.
		# Sit on our hands?
	    }
	}
    }
    if ($search_string =~ /^console$|^nanny$|^Nanny$/) {
	$location = &geolocate_ip_win32($config->{'ip'});
	if ($location =~ /,.* - .+/) {
	    $location = '"Этот сервер находится в районе ^2"' . $location;
	} else {
	    $location = '"Этот сервер находится в ^2"' . $location;
	}
	&rcon_command("say $location");
	print "$location\n";
	# sleep 1;
    }

        
}
# END: locate()

# BEGIN: rcon_status()
sub rcon_status {
    my $status = &rcon_query('status');
    
    print "$status\n";
    my @lines = split(/\n/,$status);
    my $line;
    my $slot;
    my $score;
    my $ping;
    my $guid;
    my $remainder;
    my $rate;
    my $qport;
    my $ip;
    my $port;
    my $lastmsg;
    my $name;
    my $colorless;
    foreach $line (@lines) {
	if ($line =~ /^\s+(\d+)\s+(-?\d+)\s+([\dCNT]+)\s+(\d+)\s+(.*)/) {
	    ($slot,$score,$ping,$guid,$remainder) = ($1,$2,$3,$4,$5);
	    
	    # rate
	    if ($remainder =~ /\s+(\d+)\s*$/) {
		$rate = $1;
		$remainder =~ s/\s+(\d+)\s*$//;
	    } else { 
		print "Skipping malformed line: $line\n";
		next;
	    }
	    
	    # qport
	    if ($remainder =~ /\s+(\d+)$/) {
		$qport = $1;
		$remainder =~ s/\s+(\d+)\s*$//;
	    } else {
		print "Skipping malformed line: $line\n";
		next;
	    }
	    
	    # ip and port
	    if ($remainder =~ /\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):([\d\-]+)$/) {
		($ip,$port) = ($1,$2);
		$remainder =~ s/\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):([\d\-]+)$//;
	    } elsif ($remainder =~ /\s+loopback$/) {
		($ip,$port) = ($config->{'ip'},'31337');
		$remainder =~ s/\s+loopback$//;
	    } else {
		print "Skipping malformed line: $line\n";
		next;
	    }
	    # lastmsg
	    if ($remainder =~ /\s+(\d+)$/) {
		$lastmsg = $1;
		$remainder =~ s/\s+(\d+)\s*$//;
	    } else {
		print "Skipping malformed line: $line\n";
		next;
	    }
	    
	    # lastmsg
	    if ($remainder =~ /(.*)\^7$/) {
		$name = $1;
		# strip trailing spaces.
		$name =~ s/\s+$//;
	    } else {
		print "Skipping malformed line: $line\n";
		next;
	    }
	    
	    # Name sanity check.  New rcon library gets crazy sometimes.
	    if (length($name) > 31) {
		print "DEBUG: Skipping Malformed Name: $name\n";
		next;
	    }
	   

	    # we know at this point that the line is complete.
	    # the record is intact
	    
	    # cache the name
	    &update_name_by_slot($name, $slot);

	    # cache the guid
	    $guid_by_slot{$slot} = $guid;

            # cache slot to IP mappings
            $ip_by_slot{$slot} = $ip;

	    # cache the ip to guid mapping
	    if ($guid) { &cache_ip_to_guid($ip,$guid); }

	    # cache the guid_to_name mapping
	    if ($guid) { &cache_guid_to_name($guid,$name); }

	    # cache the ip to name mapping
	    &cache_ip_to_name($ip,$name);
	    
	    # cache names without color codes, too.
	    $colorless = &strip_color($name);
	    if ($colorless ne $name) { 
		&cache_ip_to_name($ip,$colorless);
		if ($guid) { &cache_guid_to_name($guid,$colorless); }
	    }
	    
	    # GUID Sanity Checking - detects when the server is not tracking GUIDs correctly.
	    if ($guid) {
		# we know the GUID is non-zero.  Is it the one we most recently saw join?
		if (($guid == $most_recent_guid) && ($slot == $most_recent_slot)) {
		    # was it recent enough to still be cached by activision?
		    if ( ($time - $most_recent_time) < (2 * $rconstatus_interval) ) {
			# Is it time to run another sanity check?
			if ( ($time - $last_guid_sanity_check) > $guid_sanity_check_interval ) {
                            &guid_sanity_check($guid,$ip);
			}
		    } 
		}
	    }
	    
	    # Ping-related checks. (Known Bug:  Not all slots are ping-enforced, rcon can't always see all the slots.)
	    if ($ping ne 'CNCT') {
		if ($ping == 999) {
		    if (!defined($last_ping{$slot})) { $last_ping{$slot} = 0; }
		    if (($last_ping{$slot} == 999) && ($config->{'ping_enforcement'}) && ($config->{'999_quick_kick'})) {
			print "999 ping for $name\n";
			&rcon_command("say " . "$name" . '" ^7был выкинут за 999 пинг."');
			sleep 1;
			&rcon_command("clientkick $slot");
			&log_to_file('logs/kick.log', "PING: $name was kicked for having a 999 ping for too long");
		    }
		} else {
		    if (!defined($ping_average{$slot})) { $ping_average{$slot} = 0; }
		    $ping_average{$slot} = int ( ( $ping_average{$slot} * 0.85  ) + ( $ping * 0.15 ) );
		    if (($config->{'ping_enforcement'}) && ($ping_average{$slot} > ($config->{'max_ping_average'}))) {
			&rcon_command("say $name " . '"^7 был выкинут за слишком высокий пинг."' . " ($ping_average{$slot} / 350)");
			&log_to_file('logs/kick.log', "$name was kicked for having too high of an average ping. ($ping_average{$slot} / 350)");
			sleep 1;
			&rcon_command("clientkick $slot");
		    }
		}

		# we need to remember this for the next ping we check.
		$last_ping{$slot} = $ping;
	    }
	    # End of Ping Checks.

	}
    }
    
    my @row;
    my $sth = $ip_to_name_dbh->prepare("SELECT ip FROM ip_to_name WHERE name=? ORDER BY id DESC LIMIT 1");
    # BEGIN: IP Guessing - if we have players who we don't get IP's with status, try to fake it.
    foreach $slot (sort { $a <=> $b } keys %name_by_slot) {
	if ($slot >= 0) {
	    if ((!defined($ip_by_slot{$slot})) || ($ip_by_slot{$slot} eq 'not_yet_known')) {
		$ip_by_slot{$slot} = 'unknown';
		$sth->execute($name_by_slot{$slot}) or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
		while (@row = $sth->fetchrow_array) {
		    $ip_by_slot{$slot} = $row[0] . '?';
		    print "Guessed an IP for: $name_by_slot{$slot} =  $ip_by_slot{$slot} \n";
		}
	    }
	    # extra noise - not needed now that we have full rcon output.
#	    if ((defined($name_by_slot{$slot})) && ($name_by_slot{$slot} ne 'SLOT_EMPTY') &&
#		(defined($ip_by_slot{$slot})) && ($ip_by_slot{$slot} ne 'SLOT_EMPTY')) {
#		print "slot $slot:  Name: $name_by_slot{$slot}  IP: $ip_by_slot{$slot}  \n";
#	    }
	}
    }
    # END:  IP Guessing from cache

    # BEGIN: Check for Banned IP addresses
    my $stripped;

    # TABLE bans (id INTEGER PRIMARY KEY, ban_time INTEGER, unban_time INTEGER, ip VARCHAR(15), guid INTEGER, name VARCHAR(64) );
    $sth = $bans_dbh->prepare("SELECT * FROM bans WHERE ip=? AND unban_time > $time ORDER BY id DESC LIMIT 1");
    foreach $slot (sort { $a <=> $b } keys %ip_by_slot) {
        if ($slot >= 0) {
	    $stripped = $ip_by_slot{$slot};
	    # $stripped =~ s/\?$//;
	    $sth->execute($stripped);
	    while (@row = $sth->fetchrow_array) {
		&rcon_command("say ^1$name_by_slot{$slot}^7: " . '"Вы забанены.  Вы не можете остатся на этом сервере."');
		sleep 1;
		&rcon_command("say " . '"игрок"' .  "^1$row[5]" . '"^7был забанен "' . scalar(localtime($row[1])) . " - (BAN ID#: $row[0])");
		sleep 1;
		if ($row[2] == 2125091758) {
		    &rcon_command("say ^1$name_by_slot{$slot}^7: " . '"У вас перманентный бан."');
		} else {		    
		    &rcon_command("say ^1$name_by_slot{$slot}^7:" . '" Вы будете разбанены "' . &duration( ( $row[2]) - $time ) );
		}
		sleep 1;
		&rcon_command("clientkick $slot");
		sleep 1;
		&log_to_file('logs/kick.log', "KICK: BANNED: $name_by_slot{$slot} was kicked - banned IP: $ip_by_slot{$slot}  ($row[5]) - (BAN ID#: $row[0])");
	    }
	}
    }    
    # END: Banned IP Address check
    
}
# END: rcon_status()


# BEGIN: rcon_command($command)
sub rcon_command {
    my ($command) = @_;
    
    # odd bug regarding double slashes.
    $command =~ s/\/\/+/\//g;

    if ($config->{'show_rcon'}) {
	print "RCON: $command\n";
    }

    print $rcon->execute($command);
    sleep 1;
    
    if (my $error = $rcon->error()) {
	# rcon timeout happens after the object has been in use for a long while.
	# Try rebuilding the object
	if ($error eq 'Rcon timeout') {
	    print "rebuilding rcon object\n";
	    $rcon = new KKrcon(
			       Host => $config->{'ip'},
			       Port => $config->{'port'},
			       Password => $config->{'rcon_pass'},
			       Type => 'old'
			       );
	    
	} else { print "WARNING: rcon_command error: $error\n"; }
	
	return 1;
    } else {
	return 0;
    }
}
# END: rcon_command()


# BEGIN: rcon_query($command)
sub rcon_query {
    my ($command) = @_;
    
    if ($config->{'show_rcon'}) {
        print "RCON: $command\n";
    }

    my $result = "rcon_command error";
    $result = $rcon->execute($command);
    sleep 1;
    
    if (my $error = $rcon->error()) {
	# rcon timeout happens after the object has been in use for a long while.
        # Try rebuilding the object
        if ($error eq 'Rcon timeout') {
            print "rebuilding rcon object\n";
            $rcon = new KKrcon(
                               Host => $config->{'ip'},
                               Port => $config->{'port'},
                               Password => $config->{'rcon_pass'},
                               Type => 'old'
                               );
	    
        } else { print "WARNING: rcon_command error: $error\n"; }
	
	return $result;
    }
    else { return $result; }
}
# END: rcon_query


# BEGIN: geolocate_ip_win32
sub geolocate_ip_win32 {
    my $ip = shift;
    my $metric = 0;
    if (!defined($ip)) { return '"Неверный IP"'; }
	
	if ($ip =~ /^192\.168\.|^10\.|localhost|loopback|^169\.254\./) { return '"^2своей локальной сети"'; }
	
    if ($ip !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) { return '"Неверный IP адрес:  "' . "$ip"; }
	
    my $gi = Geo::IP->open("databases/GeoLiteCity.dat", GEOIP_STANDARD);

    my $record = $gi->record_by_addr($ip);

    if (!defined($record)) { return '"ниоткуда..."'; }

    # region code is built as COUNTRY.REGION
    my $region_code = $record->country_code . '.' . $record->region;

    # check the database for this region code
    my $region_name = $record->region_name;
    #my $sth = $region_names_dbh->prepare("SELECT region_name FROM region_names WHERE region_code=?");
    #$sth->execute($region_code) or &die_nice("Unable to execute query: $region_names_dbh->errstr\n");
    #my @row = $sth->fetchrow_array;
    #if ($row[0]) {
    #    $region_name = $row[0];
    #} else {
    #    print "DEBUG: no region code for $region_code\n";
    #}
    # end of database region lookup

    my $geo_ip_info;

    if (defined($record->city) ) {
        # we know the city
        if (defined($region_name)) {
            # and we know the region name
            if ($record->city ne $region_name) {
                # the city and region name are different, all three are relevant.
                $geo_ip_info = $record->city . ', ' . $region_name . ' - ' . $record->country_name;
            } else {
                # the city and region name are the same.  Use city and country.
                $geo_ip_info = $record->city . ', ' . $record->country_name;
            }
        } else {
            # Only two pieces we have are city and country.
            $geo_ip_info = $record->city . ', ' . $record->country_name;
        }
    } elsif (defined($region_name)) {
        # don't know the city, but we know the region name and country.  close enough.
        $geo_ip_info = "$region_name, " . $record->country_name;
    } elsif (defined($record->country_name)) {
        # We may not know much, but we know the country.
        $geo_ip_info = $record->country_name;
    } elsif (defined($record->country_code)) {
        # How about a 2 letter country code at least?
        $geo_ip_info = $record->country_code;
    } else {
        # I give up.
        $geo_ip_info = '"ниоткуда"';
    }

    # debugging
    print "
        Country Code: " . $record->country_code . "
        Country Code 3: " . $record->country_code3 . "
        Country Name: " . $record->country_name . "
        Region: " . $record->region . "
		Region Name: " . $record->region_name . "
        City: " . $record->city . "
        Postal Code: " . $record->postal_code . "
        Lattitude: " . $record->latitude . "
        Longitude: " . $record->longitude . "
		Time Zone: " . $record->time_zone . "
        Area Code: " . $record->area_code . "
		Continent Code: " . $record->continent_code . "
		Metro Code " . $record->metro_code . "
		\n";


    if ((defined($record->country_code)) && ($record->country_code eq 'US')) { $metric = 0 }
    else { $metric = 1; }
    print "DEBUG: country code = " . $record->country_code . "\n";
    print "DEBUG: metric = $metric\n"; 

    # GPS Coordinates
    if (($config->{'ip'} !~ /^192\.168\.|^10\.|^169\.254\./))
    {
	if ((defined($record->latitude)) && (defined($record->longitude)) && ($record->latitude =~ /\d/)) {
	    my ($player_lat, $player_lon) = ($record->latitude, $record->longitude);
	    # gps coordinates are defined for this IP.
	    # now make sure we have coordinates for the server.
	    
	    $record = $gi->record_by_name($config->{'ip'});
	    if ((defined($record)) && (defined($record->latitude)) && (defined($record->longitude)) && ($record->latitude =~ /\d/)) {
		my ($home_lat, $home_lon) = ($record->latitude, $record->longitude);
		my $obj = Geo::Inverse->new(); 
		my $dist = $obj->inverse($player_lat, $player_lon , $home_lat, $home_lon);
		if ($metric) {
                    $dist = int($dist/1000);
                    $geo_ip_info .= " ^7$dist" . '" километров до сервера"';
		} else {
		    $dist = int($dist/1609.344);
                    $geo_ip_info .= " ^7$dist" . '" миль до сервера"';
		}
	    }
	}
    }

    return $geo_ip_info;
}
# END geolocate_ip_win32


# BEGIN: cache_ip_to_guid($ip,$guid)
sub cache_ip_to_guid {
    my $ip = shift;
    my $guid = shift;
    
    # idiot gates
    if (!defined($guid)) { 
	&die_nice("cache_ip_to_guid() was called without a guid number\n");
    } elsif ($guid !~ /^\d+$/) { 
	&die_nice("cache_ip_to_guid() guid was not a number: |$guid|\n");
    } elsif (!defined($ip)) {
	&die_nice("cache_ip_to_guid() was called without an ip\n");
    }
    
    if ($guid) {
	# only log this if the guid isn't zero
	my $sth = $ip_to_guid_dbh->prepare("SELECT count(*) FROM ip_to_guid WHERE ip=? AND guid=?");
	$sth->execute($ip,$guid) or &die_nice("Unable to execute query: $ip_to_guid_dbh->errstr\n");
	my @row = $sth->fetchrow_array;
	if ($row[0]) { }
	else { 
	    &log_to_file('logs/guid.log', "New IP to GUID mapping: $ip - $guid");
	    print "New IP to GUID mapping: $ip - $guid\n";
	    $sth = $ip_to_guid_dbh->prepare("INSERT INTO ip_to_guid VALUES (NULL, ?, ?)");
	    $sth->execute($ip, $guid) or &die_nice("Unable to do insert\n");
	}
    }
}
# END: cache_ip_to_guid()

# BEGIN: cache_ip_to_name($ip,$name)
sub cache_ip_to_name {
    my $ip = shift;
    my $name = shift;
    
    # idiot gates
    if (!defined($name)) { 
	&die_nice("cache_ip_to_name() was called without a name\n");
    } elsif (!defined($ip)) {
	&die_nice("cache_ip_to_name() was called without an ip\n");
    }
    
    my $sth = $ip_to_name_dbh->prepare("SELECT count(*) FROM ip_to_name WHERE ip=? AND name=?");
    $sth->execute($ip,$name) or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
    my @row = $sth->fetchrow_array;
    if ($row[0]) { }
    else { 
	&log_to_file('logs/guid.log', "Caching IP to NAME mapping: $ip - $name");
	print "Caching IP to NAME mapping: $ip - $name\n"; 
	$sth = $ip_to_name_dbh->prepare("INSERT INTO ip_to_name VALUES (NULL, ?, ?)");
	$sth->execute($ip, $name) or &die_nice("Unable to do insert\n");
    }
}
# END: cache_ip_to_name()


# BEGIN: seen($search_string)
sub seen {
    my $search_string = shift;
    
    # print "Searching Seen for: $search_string\n";
    
    my $sth = $seen_dbh->prepare("SELECT name,time,saying FROM seen WHERE name LIKE ? ORDER BY time DESC LIMIT 5");
    $sth->execute("\%$search_string\%") or &die_nice("Unable to execute query: $seen_dbh->errstr\n");
    my @row;
    
    if (&flood_protection('seen', (10 + ( $sth->rows * 5 ) ), $slot)) { return 1; }

    while (@row = $sth->fetchrow_array) {
	&rcon_command("say " . " $row[0] " . '" ^7был замечен на сервере "' . "" . duration($time - $row[1]) . "" . '" назад, и сказал:"' . '"' . " $row[2]");
	print "SEEN: $row[0] was last seen " . duration($time - $row[1]) . " ago, saying: $row[2]\n";
	sleep 1;
    }
}
# END: seen()

# BEGIN: log_to_file($file, $message)
sub log_to_file {
    my ($logfile,$msg) = @_;
    open LOG, ">> $logfile" || return 0;
    print LOG "$timestring: $msg\n";
    close LOG;
}
# END: log_to_file()

# BEGIN: stats($search_string)
sub stats {
    my $name = shift;
    my $search_string = shift;

    if (&flood_protection('stats', 300, $slot)) { return 1; }

    if ($search_string ne '') {
	
	my @matches = &matching_users($search_string);
	if ($#matches == 0) {
	    # $name = &strip_color($name_by_slot{$matches[0]});
	    $name = $name_by_slot{$matches[0]};
	} elsif ($#matches > 0) {
	    &rcon_command("say " . '"Слишком много совпадений для: "' . "$search_string" . " , ^7введите более точные данные.");
	    # sleep 1;
	    return 1;
	}

    }
    # print "DEBUG: $name is set to: $name\n";

    my $stats_msg = " " . '"Статистика^2"' . "$name^7:";
    my $kills = 1;

    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE name=?");
    $stats_sth->execute($name) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    @row = $stats_sth->fetchrow_array;
    if ((!$row[0]) && ($name ne &strip_color($name))) {
	$stats_sth->execute(&strip_color($name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	@row = $stats_sth->fetchrow_array;
    }
    if ($row[0]) {
	$stats_msg .= " ^1$row[2]" . '"^7убийств,"' . "^1$row[3]" . '"^7смертей,"' . "^1$row[4]" . '"^7хедшотов,"';
	$kills = $row[2];
	if ($row[3]) { 
	    my $k2d_ratio = int($row[2] / $row[3] * 100) / 100;
	    $stats_msg .= "" . '"^7 рейтинг -^7"' . " ^1 $k2d_ratio^7, ";
	} else {
	    $stats_msg .= "" . '"^7 рейтинг -^7"';
	}
	if ($row[2]) {
	    my $headshot_percent = int($row[4] / $row[2] * 10000) / 100;
	    $stats_msg .= "^1$headshot_percent" . '"^7процент хедшотов"';
	} 
    }
    else {
	$stats_sth = $stats_dbh->prepare("INSERT INTO stats VALUES (NULL, ?, ?, ?, ?)");
	$stats_sth->execute($name, 0, 0, 0) or &die_nice("Unable to do insert\n");
	$stats_msg = '"Не найдено статистики для:"' . "$name";
    }

    &rcon_command("say $stats_msg");
    print "$stats_msg\n"; 
    sleep 1; 


    # 2nd generation stats;
    # id,name,pistol_kills,grenade_kills,bash_kills,shotgun_kills,sniper_kills,rifle_kills,machinegun_kills,best_killspree,nice_shots,bullshit_shots
    # 0  1    2            3             4          5             6            7           8                9              10         11
    $stats_msg = " " . '"Статистика^2"' . "$name^7:";
    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats2 WHERE name=?");
    $stats_sth->execute($name) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    @row = $stats_sth->fetchrow_array;
    if ((!$row[0]) && ($name ne &strip_color($name))) {
        $stats_sth->execute(&strip_color($name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
        @row = $stats_sth->fetchrow_array;
    }
    if (($row[0]) && $kills) {
	my $pistol_ratio = ($row[2]) ? int($row[2] / $kills * 10000) / 100 : 0;
	my $grenade_ratio = ($row[3]) ? int($row[3] / $kills * 10000) / 100 : 0;
	my $bash_ratio = ($row[4]) ? int($row[4] / $kills * 10000) / 100 : 0;
	my $best_killspree = $row[9];
	$stats_msg .= " ^1$pistol_ratio" . '"^7пистолетов,"' . "^1$grenade_ratio" . '"^7гранат,"' . "^1$bash_ratio" . '"^7ближнего боя"';
	
	if (($row[2]) || ($row[3]) || ($row[4])) { 
	    &rcon_command("say $stats_msg");
	    print "$stats_msg\n";
	    sleep 1;
	}

	# shotgun_kills,sniper_kills,rifle_kills,machinegun_kills
	$stats_msg = " " . '"Статистика^2"' . "$name^7:";
	my $shotgun_ratio = (($row[5]) && ($kills)) ? int($row[5] / $kills * 10000) / 100 : 0;
        my $sniper_ratio = (($row[6]) && ($kills)) ? int($row[6] / $kills * 10000) / 100 : 0;
        my $rifle_ratio = (($row[7]) && ($kills)) ? int($row[7] / $kills * 10000) / 100 : 0;
	my $machinegun_ratio = (($row[8]) && ($kills)) ? int($row[8] / $kills * 10000) / 100 : 0;
	my $bullshit_ratio = (($row[11]) && ($kills)) ? int($row[11] / $kills * 1000000) / 10000 : 0;
        $stats_msg .= " ^7^1$shotgun_ratio" . '"^7дробовиков,"' . "^1$sniper_ratio" . '"^7снайп.винтовок,"' . "^1$rifle_ratio" . '"^7винтовок,"' . "^1$machinegun_ratio" . '"^7полу-автоматов"';

	if (($row[5]) || ($row[6]) || ($row[7]) || ($row[8])) {
	    &rcon_command("say $stats_msg");
	    print "$stats_msg\n";
	    sleep 1;
	} 

    # best killing spree 
	if ($best_killspree) {
	    $stats_msg = " " . '"Статистика^2"' . "$name^7:";
	    $stats_msg .= "^7" . '"Лучшая серия убийств -^1"' . "$best_killspree";
	    &rcon_command("say $stats_msg");
	    print "$stats_msg\n";
	    sleep 1;
	}

	if (($row[11]) && ($config->{'bullshit_calls'})) {
	    $stats_msg = " " . '"Статистика^2"' . "$name^7:";
	    $stats_msg .= " Bullshit kills: ^1$row[11] ^7calls (^1$bullshit_ratio ^7percent)";
	    &rcon_command("say $stats_msg");
	    print "$stats_msg\n";
	    sleep 1;
	}
    }
}
# END: stats()


# BEGIN: check_access($attribute_name)
sub check_access {
    my $attribute = shift;
    
    if (!defined($attribute)) { &die_nice("check_access() was called without an attribute"); }

    my $value;

    
    if (defined($config->{'auth'}->{$attribute})) {
	# Helpful globals from the chat() function
	# $name
	# $slot
	# $message
	# $guid
	
	# Check each specific attribute defined for this specific directive.
	foreach $value (split /,/, $config->{'auth'}->{$attribute}) {
	    # print "DEBUG: Auth_$attribute value = $value\n";
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
			} elsif ($value =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
			    if ($ip_by_slot{$slot} eq $value) {
				print "disabled command $attribute authenticated by IP override access: $value\n";
				return 1;
			    }
			    # Check if the IP is a wildcard match
			} elsif ($value =~ /^\d{1,3}\.\d{1,3}\.[\d\.]+\.\*$/) {
			    $value =~ s/\./\\./g;
			    if ($ip_by_slot{$slot} =~ /$value/) {
				# no guessed IPs allowed
				if ($ip_by_slot{$slot} =~ /\?$/) { print "Refusing to authenticate a guessed IP address\n"; }
				else {
				    print "disabled command $attribute authenticated by wildcard IP override access: $value\n";
				    return 1;
				}
			    }
			} else {
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
	    } elsif ($value =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
		if ($ip_by_slot{$slot} eq $value) {
		    print "$attribute command authenticated by IP: $value\n";
		    return 1;
		}
		# Check if the IP is a wildcard match
	    } elsif ($value =~ /^\d{1,3}\.\d{1,3}\.[\d\.]+\.\*$/) {
		$value =~ s/\./\\./g;
		if ($ip_by_slot{$slot} =~ /$value/) {
		    # no guessed IPs allowed
		    if ($ip_by_slot{$slot} =~ /\?$/) { print "Refusing to authenticate a guessed IP address\n"; }
		    else {
			print "$attribute command authenticated by wildcard IP: $value\n";
			return 1;
		    }
		}
	    } else {
		print "\nWARNING: unrecognized access directive:  $value\n\n"; 
	    }
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
	    } elsif ($value =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
		if ($ip_by_slot{$slot} eq $value) {
		    print "global admin access for $attribute authenticated by IP: $value\n";
		    return 1;
		}
		# Check if the IP is a wildcard match
	    } elsif ($value =~ /^\d{1,3}\.\d{1,3}\.[\d\.]+\.\*$/) {
		$value =~ s/\./\\./g;
		if ($ip_by_slot{$slot} =~ /$value/) {
		    # make sure that we dont let guessed IP's through
		    if ($ip_by_slot{$slot} =~ /\?$/) { print "Refusing to authenticate a guessed IP address\n"; }
		    else {
			print "global admin access for $attribute authenticated by wildcard IP: $value\n";
			return 1;
		    }
		}
	    } else {
		print "\nWARNING: unrecognized access directive:  $value\n\n";
	    }
	}
    }
    # Default = not allowed
    # print "WARNING:  No access attributes defined for $attribute\n";
    # print "\tdefault access = disabled   Check the config file for auth_$attribute lines\n";
    return 0;
}

# END:  check_access()


sub sanitize_regex {
    my $search_string = shift;
    if (!defined($search_string)) { 
	print "WARNING: sanitize_regex() was not passed a string\n";
	return '';
    }

    if (($search_string eq '*') || ($search_string eq '.') || ($search_string eq 'all')) { return '.'; }
    
    # print "debug sanitize_regex: INPUT: $search_string ";
    
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
    
    # print "OUTPUT: $search_string\n\n";
    
    return $search_string;
    
}

sub matching_users {
    # a generic function to do string matches on active usernames
    #  returns a list of slot numbers that match.
    my $search_string = shift;
    if ($search_string =~ /^\/(.+)\/$/) { $search_string = $1; }
    else { $search_string = &sanitize_regex($search_string); }
    print "DEBUG: search string is: $search_string\n"; 
    my $key;
    my @matches = ();
    foreach $key (keys %name_by_slot) {
	if (($name_by_slot{$key} =~ /$search_string/i) || (&strip_color($name_by_slot{$key}) =~ /$search_string/i)) {
	    print "MATCH: $name_by_slot{$key}\n";
	    push @matches, $key;
	}
    }    
    if ($#matches == -1) {
	foreach $key (keys %name_by_slot) {
	    if (&strip_color(&strip_color($name_by_slot{$key})) =~ /$search_string/i) {
		print "MATCH: $name_by_slot{$key}\n";
		push @matches, $key;
	    }
	}
    }

    return @matches;
}

# BEGIN: ignore($search_string)
sub ignore {
    my $search_string = shift;
    my $key;
    if ($search_string =~ /^\#(\d+)$/) {
        my $slot = $1;
        &rcon_command("say ^2$name_by_slot{$slot}" . '" ^7теперь будет игнорироватся."');
        # sleep 1;
	$ignore{$slot} = 1;
        &log_to_file('logs/admin.log', "!IGNORE: $name_by_slot{$slot} was ignored by $name - GUID $guid - (Search: $search_string)");
        return 0;
    }
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . "$search_string"); }
    elsif ($#matches == 0) {
        &rcon_command("say ^2$name_by_slot{$matches[0]}" . '"^7теперь будет игнорироватся."');
        # sleep 1;
        $ignore{$matches[0]} = 1;
        &log_to_file('logs/admin.log', "!IGNORE: $name_by_slot{$matches[0]} was ignored by $name - GUID $guid - (Search: $search_string)");
	
    }
    elsif ($#matches > 0) { &rcon_command("say " . '"Слишком много данных на: "' . "$search_string"); }
}


# BEGIN: forgive($search_string)
sub forgive {
    my $search_string = shift;
    my $key;
    
    # if ($search_string =~ /Cyrus/i) { 
	# &rcon_command("say I can`t do that.   Sorry, Cyrus.   You`re still a DICK.");
	# sleep 1;
	# return 0;
    # }

    if ($search_string =~ /^\#(\d+)$/) {
        my $slot = $1;
        &rcon_command("say ^2$name_by_slot{$slot}" . '"^7пообещал вести себя хорошо и был прощен админом"');
        # sleep 1;
        $ignore{$slot} = 0;
	$idle_warn_level{$slot} = 0;
	$last_activity_by_slot{$slot} = $time;
	$penalty_points{$slot} = 0;
        &log_to_file('logs/admin.log', "!FORGIVE: $name_by_slot{$slot} was forgiven by $name - GUID $guid - (Search: $search_string)");
        return 0;
    }
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . "$search_string"); }
    elsif ($#matches == 0) {
        &rcon_command("say ^2$name_by_slot{$matches[0]}" . '"^7пообещал вести себя хорошо и был прощен админом"');
        # sleep 1;
        $ignore{$matches[0]} = 0;
	$idle_warn_level{$matches[0]} = 0;
        $last_activity_by_slot{$matches[0]} = $time;
        $penalty_points{$matches[0]} = 0;
        &log_to_file('logs/admin.log', "!FORGIVE: $name_by_slot{$matches[0]} was forgiven by $name - GUID $guid - (Search: $search_string)");

    }
    elsif ($#matches > 0) { &rcon_command("say " . '" Слишком много данных на: "' . "$search_string"); }
}


# BEGIN: kick_command($search_string)
sub kick_command {
    my $search_string = shift;
    my $key;
    if ($search_string =~ /^\#(\d+)$/) {
	my $slot = $1;
	&rcon_command("say ^2$name_by_slot{$slot}" . '" ^7был выкинут админом"');
        sleep 1;
        &rcon_command("clientkick $slot");
        &log_to_file('logs/kick.log', "!KICK: $name_by_slot{$slot} was kicked by $name - GUID $guid - via the !kick command. (Search: $search_string)");
	return 0;
    }
    my @matches = &matching_users($search_string);
    if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . "$search_string"); }
    elsif ($#matches == 0) {
	&rcon_command("say ^2$name_by_slot{$matches[0]}" . '" ^7был выкинут админом"');
	sleep 1;
	&rcon_command("clientkick $matches[0]");
	&log_to_file('logs/kick.log', "!KICK: $name_by_slot{$matches[0]} was kicked by $name - GUID $guid - via the !kick command. (Search: $search_string)");
	
    }
    elsif ($#matches > 0) { &rcon_command("say Слишком много данных на: " . "$search_string"); }
}

# BEGIN: !clearstats command($search_string)
sub clear_stats {
    my $search_string = shift;
    my $victim;
	my $sth;
	my @row;
    my @matches = &matching_users($search_string);
    if ($#matches == -1) {
    &rcon_command("say No matches for: $search_string"); }
    elsif ($#matches == 0) {
	my $victim = $name_by_slot{$matches[0]};
	$sth = $stats_dbh->prepare('DELETE FROM stats where name=?;');
    $sth->execute($victim) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	$sth = $stats_dbh->prepare('DELETE FROM stats2 where name=?;');
    $sth->execute($victim) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	&rcon_command("say " . '"Удалена статистика для:"' . "$victim"); }
	elsif ($#matches > 0) { &rcon_command("say Слишком много данных на: " . "$search_string");}
}

# BEGIN: tempban_command($search_string)
sub tempban_command {
    my $search_string = shift;
    my $key;
    my $slot = 'undefined';
    if ($search_string =~ /^\#(\d+)$/) {
        $slot = $1;
    } else {    
	my @matches = &matching_users($search_string);
	if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . "$search_string"); return 0; }
	elsif ($#matches == 0) { $slot = $matches[0]; }
	elsif ($#matches > 0) { &rcon_command("say Слишком много данных на: " . "$search_string"); return 0; }
    }
    
    my $ban_ip = 'undefined';
    my $unban_time = $time + 1200;
    &rcon_command("say ^2$name_by_slot{$slot}" . '" ^7был временно забанен админом"');
    sleep 1;
    if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
	$ban_ip = $ip_by_slot{$slot};
    }
    # TABLE bans (id INTEGER PRIMARY KEY, ban_time INTEGER, unban_time INTEGER, ip VARCHAR(15), guid INTEGER, name VARCHAR(64) );
    &rcon_command("tempbanclient $slot");
    sleep 1;
    &log_to_file('logs/kick.log', "!TEMPBAN: $name_by_slot{$slot} was temporarily banned by $name - GUID $guid - via the !tempban command. (Search: $search_string)");
    
    my $bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
    $bans_sth->execute($time, $unban_time, $ban_ip, $guid_by_slot{$slot}, $name_by_slot{$slot}) or &die_nice("Unable to do insert\n");
}

# BEGIN: ban_command($search_string)
sub ban_command {
    my $search_string = shift;
    my $key;
    my $slot = 'undefined';
    if ($search_string =~ /^\#(\d+)$/) {
        $slot = $1;
    } else {
        my @matches = &matching_users($search_string);
        if ($#matches == -1) { &rcon_command("say " . '"Нет совпадений с: "' . "$search_string"); return 0; }
        elsif ($#matches == 0) { $slot = $matches[0]; }
        elsif ($#matches > 0) { &rcon_command("say Слишком много данных на: " . "$search_string"); return 0; }
    }   
    my $ban_ip = 'undefined';
    my $unban_time = 2125091758;
    &rcon_command("say ^2$name_by_slot{$slot}" . '" ^7был забанен админом"');
    sleep 1;
    if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
	$ban_ip = $ip_by_slot{$slot};
    }
    # TABLE bans (id INTEGER PRIMARY KEY, ban_time INTEGER, unban_time INTEGER, ip VARCHAR(15), guid INTEGER, name VARCHAR(64) );	
    &rcon_command("banclient $slot");
    sleep 1;
    &rcon_command("clientkick $slot");
    sleep 1;
    &log_to_file('logs/kick.log', "!BAN: $name_by_slot{$slot} was permanently banned by $name - GUID $guid - via the !ban command. (Search: $search_string)");	
    
    my $bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
    $bans_sth->execute($time, $unban_time, $ban_ip, $guid_by_slot{$slot}, $name_by_slot{$slot}) or &die_nice("Unable to do insert\n");
}


# BEGIN: &unban_command($target);
#  where $target = a ban ID # or a partial string match for names. 
sub unban_command {
    my $unban = shift;
    my $bans_sth;
    my $delete_sth; 
    my $key;
    my @row;
    my @unban_these;
    if ($unban =~ /^\#?(\d+)$/) {
	$unban = $1;
	$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE id=?");
    } else {
	$unban = '%' . $unban . '%';
	$bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE name LIKE ?");
    }
    $bans_sth->execute($unban) or &die_nice("Unable to do unban SELECT: $unban\n");
    while (@row = $bans_sth->fetchrow_array) {
	&rcon_command("say UNBANNED: $row[5]" . '" был разбанен админом"' . "   (ban id#: $row[0]" . '" удален)"');
	sleep 1;
	&rcon_command("unbanUser \"$row[5]\"");
	sleep 1;
	push (@unban_these, $row[0]);
	&log_to_file('logs/commands.log', "UNBAN: $row[5] was unbanned by an admin.   (ban id#: $row[0] deleted)");
    }
    # now clean up the database ID's.
    foreach $key (@unban_these) {
	$delete_sth = $bans_dbh->prepare("DELETE FROM bans WHERE id=?");
        $delete_sth->execute($key) or &die_nice("Unable to delete ban ID $key: unban = $unban\n");
    }

}
# END: &unban_command($target);

# BEGIN: &voting_command($state)
sub voting_command {
    my $state = shift;
    if (&flood_protection('voting', 60, $slot)) { return 1; }
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
	&rcon_command("g_allowvote 1");
	# sleep 1;
	&rcon_command("say " . '"Голосование включено."');
	$voting = 1;
        &log_to_file('logs/admin.log', "!VOTING: voting was enabled by:  $name - GUID $guid");
    } elsif ($state =~ /^(off|0|no|disabled?)$/i) {
        &rcon_command("g_allowvote 0");
        # sleep 1;
        &rcon_command("say " . '"Голосование выключено."');
	$voting = 0;
        &log_to_file('logs/admin.log', "!VOTING: voting was disabled by:  $name - GUID $guid");
    } else {
	&rcon_command("say Unrcognized vote state:  $state  ... Use: on or off");
	# sleep 1;
    }
}
# END: &voting_command()

# BEGIN: &killcam_command($state)
sub killcam_command {
    my $state = shift;
    if (&flood_protection('killcam', 60, $slot)) { return 1; } 
   if ($state =~ /^(yes|1|on|enabled?)$/i) {
        &rcon_command("scr_killcam 1");
        # sleep 1;
        &rcon_command("say " . '"Показ гибели был ВКЛЮЧЕН админом"');
        &log_to_file('logs/admin.log', "!KILLCAM: the kill-cam was enabled by:  $name - GUID $guid");
    } elsif ($state =~ /^(off|0|no|disabled?)$/i) {
        &rcon_command("scr_killcam 0");
        # sleep 1;
        &rcon_command("say " . '"Показ гибели был ВЫКЛЮЧЕН админом"');
        &log_to_file('logs/admin.log', "!KILLCAM: the kill-cam was disabled by:  $name - GUID $guid");
    } else {
        &rcon_command("say " . '"Неизвстное значение команды !killcam:"' . "  $state  " . '" Используйте: on или off"');
        # sleep 1;
    }
}
# END: &killcam_command()

# BEGIN: speed_command($speed)
sub speed_command {
    my $speed = shift;
    if ($speed =~ /^\d+$/) {
        &rcon_command("g_speed $speed");
        # sleep 1;
        &rcon_command("say Speed was set to $speed by an admin.");
        &log_to_file('logs/admin.log', "!speed: speed was set to $speed by:  $name - GUID $guid");
    } else {
        my $query = &rcon_query("g_speed");
        if ($query =~ /\"g_speed\" is: \"(\d+)\^7\"/m) {
            $speed = $1;
            &rcon_command("say ^2the ^1speed ^2is currently set to:^5 $speed");
        } else {
            &rcon_command("say sorry, cant parse the speed results.");
        }
        # sleep 1;
    }
}
# END: &speed_command()


# BEGIN: gravity_command($speed)
sub gravity_command {
    my $gravity = shift;
    if ($gravity =~ /^\d+$/) {
        &rcon_command("g_gravity $gravity");
        # sleep 1;
        &rcon_command("say Gravity was set to $gravity by an admin.");
        &log_to_file('logs/admin.log', "!gravity: gravity was set to $gravity by:  $name - GUID $guid");
    } else {
        my $query = &rcon_query("g_gravity");
        if ($query =~ /\"g_gravity\" is: \"(\d+)\^7\"/m) {
            $gravity = $1;
            &rcon_command("say ^2the ^1gravity ^2is currently set to:^5 $gravity");
        } else {
            &rcon_command("say sorry, cant parse the gravity results.");
        }

    }
}
# END: &gravity_command()



# BEGIN: glitch_command($state)
sub glitch_command {
    my $state = shift;
    if (&flood_protection('glitch', 60, $slot)) { return 1; }
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
	$config->{'glitch_server_mode'} = 1;
        &rcon_command("say Glitch mode was enabled by an admin. ^1NO KILLING NOW.");
	# sleep 1;
        &log_to_file('logs/admin.log', "!GLITCH: glitch mode was enabled by:  $name - GUID $guid");
    } elsif ($state =~ /^(off|0|no|disabled?)$/i) {
	$config->{'glitch_server_mode'} = 0;
        &rcon_command("say Glitch mode was disabled by an admin. ^2Killing is permitted now.");
	# sleep 1;
        &log_to_file('logs/admin.log', "!GLITCH: glitch mode was disabled by:  $name - GUID $guid");
    } else {
        &rcon_command("say Unrcognized glitch state:  $state  ... Use: on or off");
        # sleep 1;
    }
}
# END: &glitch_command()

# BEGIN: &awards()
sub awards {
    my @row;
    my $sth;
    my $counter = 1;

    if (&flood_protection('awards', 900, $slot)) { return 1; }
    if (&flood_protection('awards', 300)) { return 1; }

    
    # Most Kills
    $sth = $stats_dbh->prepare('SELECT * FROM stats WHERE name != "Unknown Soldier" ORDER BY kills DESC LIMIT 10;');
    $sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command('say' . '"^2Лучшие 10 игроков сервера^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
	&rcon_command('say ^3' . ($counter++) . '"^7место:"' . "^2$row[1]" . '"^7с^1"' . "$row[2]" . '"^7убийствами"' );
	sleep 1;
    }

    # Best Kill to Death ratio
    #$counter = 1;
    #sleep 1;
    #$sth = $stats_dbh->prepare('SELECT * FROM stats WHERE kills > 1000 ORDER BY (kills * 10000 / deaths) DESC LIMIT 10;');
    #$sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
   # &rcon_command('say Awards for ^2BEST KILL TO DEATH RATIO:');
   # sleep 1;
   # while (@row = $sth->fetchrow_array) {

	# Cut point - Everything below this point was restored from a slightly older backup
	# The file was damaged and partly destroyed.  
	# Everything below this point was reconstructed from the slightly-older emacs turd.
	# Remind me to teach you about free disk space, Laz.  -smug
	
#        &rcon_command('say ^3' . &nth($counter++) . "^7  place: (#$row[0])^2  $row[1]  ^7with^1  " . 
#		      ( int($row[2] / $row[3] * 100) / 100 ) . "  ^7kills per deaths" );
   #     sleep 1;
   # }

    # Best Headshot Percentages
    #$counter = 1;
    #sleep 1;
    #$sth = $stats_dbh->prepare('SELECT * FROM stats WHERE kills > 1000 ORDER BY (headshots * 10000 / kills) DESC LIMIT 10;');
    #$sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
   # &rcon_command('say Awards for ^2HIGHEST HEADSHOT PERCENTAGES:');
    #sleep 1;
    #while (@row = $sth->fetchrow_array) {
     #   &rcon_command('say ^3' . &nth($counter++) . "^7  place: (#$row[0])^2  $row[1]  ^7with^1  " .
     #                 ( int($row[4] / $row[2] * 10000) / 100 ) . "  ^7percent headshots" );
    #    sleep 1;
  # }

    # Best Kill Spree
    #$counter = 1;
    #sleep 1;
    #$sth = $stats_dbh->prepare('SELECT * FROM stats2 ORDER BY best_killspree DESC LIMIT 10;');
    #$sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    #&rcon_command('say Awards for ^2LONGEST KILLING SPREE:');
    #sleep 1;
    #while (@row = $sth->fetchrow_array) {
      #  &rcon_command('say ^3' . &nth($counter++) . "^7  place: (#$row[0])^2  $row[1]  ^7with^1 $row[9] ^7kills in a row" );
    #    sleep 1;
   # }
}



sub nth { 
    my $number = shift;
    if (!defined($number)) { return 'UNEFINED'; };
    if ($number =~ /1$/) { return $number . 'st'; }
    if ($number =~ /2$/) { return $number . 'nd'; }
    if ($number =~ /3$/) { return $number . 'rd'; }
    if ($number =~ /[4567890]$/) { return $number . 'th'; }
    return $number;
}

sub change_gametype {
    my $gametype = shift;
    if (!defined($gametype)) { 
	print "WARNING: change_gametype() was called without a game type\n";
	return;
    }
    if ($gametype !~ /^(dm|tdm|ctf|hq|sd|codjumper|phnt)$/) {
	print "WARNING: change_gametype() was called with an invalid game_type: $gametype\n";
        return;
    }
    if (&flood_protection('gametype', 120, $slot)) { return 1; }
    &rcon_command("say " . '"^2Смена режима игры на:"' . " ^3$gametype");
    &rcon_command("g_gametype $gametype");
    sleep 1;
    &rcon_command("map_restart");
    # sleep 1;
    &log_to_file('logs/commands.log', "$name change the game type to: $gametype");
}


# BEGIN: check_player_names()
sub check_player_names {
    print "Checking for bad names...\n"; 
    my $match_string;
    my $warned;
    foreach $slot (sort { $a <=> $b } keys %name_by_slot) {
	$warned = 0;
        if ($slot >= 0) {
	    foreach $match_string (@banned_names) {
		# print "DEBUG: if name: $name_by_slot{$slot} =~ $match_string\n"; 
		if ($name_by_slot{$slot} =~ /$match_string/) {

		    $warned = 1;

		    if (!defined($name_warn_level{$slot})) { $name_warn_level{$slot} = 0; }
		    
		    if ($name_warn_level{$slot} == 0) {
			print "NAME_WARN1: $name_by_slot{$slot} is using a banned name.  Match: $match_string\n";
			&rcon_command("tell $slot ^7[^3pm^7] ^1$name_by_slot{$slot} ^7" . $config->{'banned_name_warn_message_1'} );
			# sleep 1;
			$name_warn_level{$slot} = 1;
		    } elsif ($name_warn_level{$slot} == 1) {
			print "NAME_WARN2: $name_by_slot{$slot} is using a banned name.  (2nd warning) Match: $match_string\n";
                        &rcon_command("tell $slot ^7[^3pm^7] ^1$name_by_slot{$slot} ^7" . $config->{'banned_name_warn_message_2'} );
                        # sleep 1;
                        $name_warn_level{$slot} = 2;
                    } elsif ($name_warn_level{$slot} == 2) {
                        print "NAME_KICK: $name_by_slot{$slot} is using a banned name.  (3rd strike) Match: $match_string\n";
                        &rcon_command("tell $slot ^7[^3pm^7] ^1$name_by_slot{$slot} ^7" . $config->{'banned_name_kick_message'} );
                        sleep 1;
			&rcon_command("clientkick $slot");
			&log_to_file('logs/kick.log', "BANNED NAME: $name_by_slot{$slot} was kicked for having a banned name:  Match: $match_string");
		    }
		}
	    }
	}
	if ((!defined($name_warn_level{$slot})) || (!$warned)) { $name_warn_level{$slot} = 0; }
    }
}
# END: check_player_names


# BEGIN: make_announcement();
sub make_announcement {
    my $total = $#announcements;
    # sleep 1;
    my $announce = $announcements[int(rand($total))];
    print "Making Anouncement: $announce\n";
    &rcon_command("say $announce");
    # sleep 1;  
}
# END: make_announcement();


# BEGIN: aliases(search_string);
sub aliases {
    my $search_string = shift;
    my $key;
    my @matches = &matching_users($search_string);
    my @aliases;
    my @row;
    my $ip;
    my $guessed = 0;
    if ($#matches == -1) {
	if (&flood_protection('aliases-nomatch', 15, $slot)) { return 1; }
	&rcon_command("say " .  '"Нет совпадений с:"' . " $search_string");
    }
    elsif ($#matches == 0) {
	
        &log_to_file('logs/commands.log', "$name executed an !aliases search for $name_by_slot{$matches[0]}");
	
        if ($guid_by_slot{$matches[0]} > 0) {
            my $sth = $guid_to_name_dbh->prepare("SELECT name FROM guid_to_name WHERE guid=? ORDER BY id DESC LIMIT 100;");
            $sth->execute($guid_by_slot{$matches[0]}) or &die_nice("Unable to execute query: $guid_to_name_dbh->errstr\n");
            while (@row = $sth->fetchrow_array) {
                push @aliases, $row[0];
            }
        }

	$ip = $ip_by_slot{$matches[0]};
	if ($ip =~ /\?$/) {
	    $ip =~ s/\?$//;
	    $guessed = 1;
	}

        if ($ip =~ /\d+\.\d+\.\d+\.\d+/) {
            my $sth = $ip_to_name_dbh->prepare("SELECT name FROM ip_to_name WHERE ip=? ORDER BY id DESC LIMIT 100;");
            $sth->execute($ip) or &die_nice("Unable to execute query: $ip_to_name_dbh->errstr\n");
            while (@row = $sth->fetchrow_array) {
                push @aliases, $row[0];
            }
        }

        if ($#aliases == -1) { 
	    if (&flood_protection('aliases-none', 15, $slot)) { return 1; }
	    &rcon_command("say " . '"Не найдено имен для:"' . " $name_by_slot{$matches[0]}");
	}
        else {
	    # Remove the duplicates from the @aliases hash, and strip the less colorful versions of names.
            my $alias;
            my $key;
            my %alias_hash;
            foreach $alias (@aliases) {
                if (!defined($alias_hash{$alias})) {
                    # The name is not defined, consider adding it.

                    # possibilities:
                    #  1) it is a name that has more colors than what is already in the list
                    if (defined($alias_hash{&strip_color($alias)})) {
                        # This is a more colorful version of something already in the list.
                        # Toast the old name.
                        delete $alias_hash{&strip_color($alias)};
                        # Add the new one
                        $alias_hash{$alias} = 1;
                    }
                    #  2) It is not present in any form in the list.
                    # (or may be a less colorful version of what is already in the list.
                    else {
                        $alias_hash{$alias} = 1;
                    }

                    # 3) it is a name that has less colors than what is already in the list
                    foreach $key (keys %alias_hash) {
                        if (($alias ne $key) && ($alias eq &strip_color($key))) {
                            # Then we know that the alias is a less colorful version of what is already in the list.
                            delete $alias_hash{$alias};
                            last;
                        }
                    }
                }
            }
            # finally, announce the list.
	    my $found_none = 1;
	    my @announce_list = keys %alias_hash;
	    if (&flood_protection('aliases', (15 + (5 * $#announce_list)), $slot)) { return 1; }
            foreach $key (@announce_list) {
                if ($name_by_slot{$matches[0]} ne $key) {
		    if ($guessed) { &rcon_command("say $name_by_slot{$matches[0]}" . '" ^7вероятно еще играл как:"' . '"' . " $key"); }
		    else { &rcon_command("say $name_by_slot{$matches[0]}" . '" ^7еще играл как:"' . '"' . " $key"); }
		    $found_none = 0;
                }
            }
	    if ($found_none) {
		&rcon_command("say " . '"Не найдено имен для"' ." $name_by_slot{$matches[0]}");
	    }
        }
    }
    elsif ($#matches > 0) { &rcon_command("say " . '" Слишком много совпадений для:"' . " $search_string"); }


}

sub suk {
    if (&flood_protection('suk', 600, $slot)) { return 1; }
    if (&flood_protection('suk', 300)) { return 1; }

#    &rcon_command('say The ^3SUK^7 Awards:');
#    sleep 2;
#    &rcon_command('say . . . . . (the only award that really matters)');
#    sleep 2;
#    my @ranks = (
#		 "^0^o|*SUK*|^pvt^^^1F^7N^2G",
#		 "^1Bad^9robot^4 exSGT",
#                 "Minty",
#		 "SUGARFROSTEDMUFFIN",
#		 "|-ATS-|F.M.AquaMan",
#		 "Grisu Drache Chuckeroorooroo",
#		 "console",
#		 "Doug",
#		 "^9[^8SUK^9]^1^cook^^3Accident"
#		 );
#    foreach my $nth (0..$#ranks) {
#	&rcon_command('say ^3' . &nth($nth + 1) . "^7  place:^2  $ranks[$nth]");
#	sleep 2;
#    }
    
    my @row;
    my $sth;
    my $counter = 1;

    # sleep 1;

    $sth = $stats_dbh->prepare('SELECT * FROM stats ORDER BY deaths DESC LIMIT 10;');
    $sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    &rcon_command('say' . '"^1Наибольшее количество смертей^7:"');
    sleep 1;
    while (@row = $sth->fetchrow_array) {
        &rcon_command('say ^3' . ($counter++) . "^7" . '"место:^2"' . "$row[1]" . '"^7с^1"' . "$row[3]" . '"^7смертями"' );
        sleep 1;
    }

    #$counter = 1;
   # sleep 1;
    #$sth = $stats_dbh->prepare('SELECT * FROM stats WHERE ((kills > 1000) and (deaths > 1)) ORDER BY (kills * 10000 / deaths) ASC LIMIT 5;');
    #$sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    #&rcon_command('say ^3SUK^7 Awards for ^2WORST KILL TO DEATH RATIO:');
    #sleep 1;
    #while (@row = $sth->fetchrow_array) {
      #  &rcon_command('say ^3' . &nth($counter++) . "^7  place:^2  $row[1]  ^7with^1  " .
       #               ( int($row[2] / $row[3] * 100) / 100 ) . "  ^7kills per deaths" );
     #   sleep 1;
    #}

   # $counter = 1;
   # sleep 1;
    #$sth = $stats_dbh->prepare('SELECT * FROM stats WHERE ((kills > 1000) and (headshots > 1)) ORDER BY (headshots * 10000 / kills) ASC LIMIT 5;');
    #$sth->execute() or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
   # &rcon_command('say ^3SUK^7 Awards for ^2LOWEST HEADSHOT PERCENTAGES:');
   # sleep 1;
   # while (@row = $sth->fetchrow_array) {
      #  &rcon_command('say ^3' . &nth($counter++) . "^7  place:^2  $row[1]  ^7with^1  " .
    #   #               ( int($row[4] / $row[2] * 10000) / 100 ) . "  ^7percent headshots" );
    #    sleep 1;
    #}
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

    # begin import from ip_to_guid.pl
    my $total_tries = 5; # The total number of attempts to get an answer out of activision.
    my $read_timeout = 4; # Number of seconds to wait for activison to respond to a packet.
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

    socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp"))
	or die "Socket error: $!";

    my $random = int(rand(7654321));
    my $send_message = "\xFF\xFF\xFF\xFFgetIpAuthorize $random $ip_address  0";

    # $d_ip   = inet_aton($ip_address);
    $d_ip = gethostbyname($activision_master);

    my $selecta = IO::Select->new();
    $selecta->add(\*SOCKET);
    my @ready;

    while (($current_try++ < $total_tries) && ($still_waiting)) {
    # Send the packet
	$portaddr = sockaddr_in($port, $d_ip);
	send(SOCKET, $send_message, 0, $portaddr) == length($send_message)
	    or die "cannot send to $ip_address($port): $!\n\n";
	
	# Check to see if there is a response yet.
	@ready = $selecta->can_read($read_timeout);
	if (defined($ready[0])) {
	    # Yes, the socket is ready.
	    $portaddr = recv(SOCKET, $message, $maximum_lenth, 0)
		or die "Socket error: recv: $!";
	    # strip the 4 \xFF bytes at the begining.
	    $message =~ s/^.{4}//;
	    $got_response = 1;
	    $still_waiting = 0;
	} else {
	    print "No response from $activision_master   Trying again...\n\n";
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
		print "\t  Activision has not heard a key from this IP recently.\n";
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
		if ($guid == $should_be_guid) {
		    print "\nOK: GUID Sanity check: PASSED\n\n";
		} else {

		    &rcon_command("say ^1WARNING: ^7GUID Sanity Check failed for $name_by_slot{$most_recent_slot}");

		    print "\nFAIL: GUID Sanity check: FAILED\n";
		    print "    IP: $ip was supposed to be GUID $should_be_guid but came back as $guid\n\n";

		    &log_to_file('logs/guid.log', 
	 "SANITY FAILED: $name_by_slot{$most_recent_slot}  IP: $ip was supposed to be GUID $should_be_guid but came back as $guid - Server has been up for: $uptime");

		}
	    }

	} else {
	    print "\nERROR:\n\tGot a response, but not in the format expected\n";
	    print "\t$message\n\n";
	}
    } else {
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

    # Exemption for global admins
    if (&check_access('flood_exemption')) {
	return 0;
    }

    # Ensure that all values are defined.
    if ((!defined($min_interval)) || ($min_interval !~ /^\d+$/)) { $min_interval = 60; }
    if ((!defined($slot)) || ($slot !~ /^\d+$/)) { $slot = 'global'; }
    my $key = $attribute . '.' . $slot;
    if (!defined($flood_protect{$key})) { $flood_protect{$key} = 0; }
    if ($time >= $flood_protect{$key}) {
	# The command is allowed
	$flood_protect{$key} = $time + $min_interval;
	return 0;
    } else {
	# Too soon,  flood protection triggured.
	print "Flood protection activated.  '$attribute' command not allowed to be run again yet.\n";
	print "\tNot allowed to run for another  " . &duration(($flood_protect{$key} - $time)) . "\n";
	
	&log_to_file('logs/flood_protect.log', 
	   "Denied command access to $name for $attribute.  Not allowed to run for another  " .
	    &duration(($flood_protect{$key} - $time)) );

	# impart a small penalty for triggering the flood protection
	if ($slot ne 'global') {
	    if (!defined($penalty_points{$slot})) { $penalty_points{$slot} = 1; }
            else { $penalty_points{$slot} += 1; }
	}
	return 1;
    }
}
# END: &flood_protection()


# BEGIN: &tell($search_string,$message);
sub tell {
    my $search_string = shift;
    my $message = shift;
    my $key;
    if ((!defined($search_string)) || ($search_string !~ /./)) {
	return 1;
    }
    if ((!defined($message)) || ($message !~ /./)) {
        return 1;
    }

    my @matches = &matching_users($search_string);

    if ($#matches == -1) {
        if (&flood_protection('tell-nomatch', 15, $slot)) { return 1; }
        &rcon_command("say No matches for: $search_string");
    }
    else {
        if (&flood_protection('tell', 60, $slot)) { return 1; }
	foreach $key (@matches) {
	    &rcon_command("say ^2" . $name_by_slot{$key} . "^7: " . $message);
	    # sleep 1;
	}
    }
}
# END: &tell($search_string,$message);



# BEGIN: &assrape($search_string);
sub assrape {
    my $search_string = shift;
    my $key;
    my @matches = &matching_users($search_string);
    my @aliases;
    if ($#matches == -1) {
        if (&flood_protection('assrape-nomatch', 15, $slot)) { return 1; }
        &rcon_command("say No matches for: $search_string");
    }
    elsif ($#matches == 0) {
	if (&flood_protection('assrape', 60, $slot)) { return 1; }
	my $victim = $name_by_slot{$matches[0]};
	my @possible = (
			"^6* ^2Nanny ^3gives^1 $victim ^3a quick ass-raping.",
			"^6* ^2Nanny ^3gives^1 $victim ^3a good old-fashioned Crisco based corn-holing.",
                        "^6* ^2Nanny ^3gives^1 $victim ^3a long and brutal ass-raping",
                        "^6* ^2Nanny ^3bends^1 $victim ^3over the hood of a blue Chevy and fucks^1 $victim ^3in the ass",
                        "^6* ^2Nanny ^3delivers^1 $victim ^3a brutal and violent ass-raping ",
                        "^6* ^2Nanny ^3examines the size of^1 $victim`s^3 mouth and runs some calculations",
                        "^6* ^2Nanny ^3gives^1 $victim ^3an assraping they won't soon forget.",
                        "^6* ^2Nanny ^3dispenses a swift assrape to^1 $victim",
			"^6*^1 $victim^7:^3 This is going to hurt you a lot more than it hurts me.",
                        "^6* ^2Nanny ^3pins down^1 $victim ^3and skull fucks them till they puke.",
			);
	my $random = $possible[int(rand($#possible))];
	&rcon_command("say $random");
	# sleep 1;
    }
    elsif ($#matches > 0) { 
	&rcon_command("say Too many matches for: $search_string");
	# sleep 1;
    }

}
# END: &assrape($search_string);


# BEGIN: &last_bans($number);
sub last_bans {
    my $number = shift;
    # keep some sane limits.
    if ($number > 50) { $number = 50; }
    if ($number < 0) { $number = 1; }
    $number = int($number);
    if (&flood_protection('lastbans', 60, $slot)) { return 1; }
    

    my $bans_sth = $bans_dbh->prepare("SELECT * FROM bans WHERE unban_time=2125091758 ORDER BY id DESC LIMIT $number");
    $bans_sth->execute or &die_nice("Unable to do select recent bans\n");
    
    my @row;
    my ($ban_id, $ban_time, $unban_time, $ban_ip, $ban_guid, $ban_name);
    
    while (@row = $bans_sth->fetchrow_array) {
	($ban_id, $ban_time, $unban_time, $ban_ip, $ban_guid, $ban_name) = @row;
	my $txt_time = &duration($time - $ban_time);
        &rcon_command("say ^2$ban_name" . '" ^7был забанен"' . " $txt_time" . '" назад"' . " (ban id#: ^1$ban_id^7)");
        sleep 1;
    }


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
    my @row;
    my $sth;

    if (!defined($word)) { 
	&rcon_command("say ^1!define ^5what?");
	# sleep 1;
	return 1;
    }

    # If we are being asked to define a word, define it and return
    if ($word =~ /(.*)\s+=\s+(.*)/) {
	($term,$definition) = ($1,$2);
	$term =~ s/\s*$//;
	if (&check_access('add_definition')) {
	    $sth = $definitions_dbh->prepare("INSERT INTO definitions VALUES (NULL, ?, ?)");
	    $sth->execute($term,$definition) or &die_nice("Unable to do insert\n");
	    &rcon_command("say " . '" ^2Добавлено определение для: "' . "^1$term");
	    # sleep 1;
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
	if ($#definitions < 8) {
	    push (@definitions, "^$counter$counter^3) ^2 $row[0]");
	}
    }

    # Now we sanatize what we're looking for - online databases don't have multiword definitions.
    if ($word =~ /[^A-Za-z\-\_\s\d]/) {
	&rcon_command("say " . '" Неверный ввод, разрешены только английские буквы, точки, пробелы и цифры"');
        # sleep 1;
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
	    if ($#definitions < 8) {
		push (@definitions, "^$counter$counter^3) ^2 $row[0]");
	    }
	}
	
    } else {
	$content = get("http://wordnetweb.princeton.edu/perl/webwn?s=" . $word);
	if (!defined($content)) {
	    &rcon_command("say " . '"Словарь английского языка в настоящее время недоступен, попробуйте позже"');
	    # sleep 1;
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
		if ($#definitions < 8) {
		    push (@definitions, "^$counter$counter^3) ^2 $definition");
		}
		
	    }
	}
	$sth = $definitions_dbh->prepare("INSERT INTO cached VALUES (NULL, ?)");
	$sth->execute($word) or &die_nice("Unable to do insert into dictionary - cached table\n");

    }
    
    if (!$counter) {
	&rcon_command("say " . '"^7К сожалению, не найдено определений для слова:"' . "^2$word");
        # sleep 1;
    } else {
        if ($counter == 1) { 
	    &rcon_command("say " . '"^21 ^7определение найдено для слова:"' . "^2$word");
	} else { 
	    &rcon_command("say ^2$counter " . '"^7определений найдено для слова:"' . "^2$word");
	}
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
	if (
	    (defined($guid_by_slot{$slot})) &&
	    (defined($ip_by_slot{$slot})) &&
	    ($guid_by_slot{$slot} == 0) &&
	    ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
	    ) 
	{ 
	    push @possible, $slot;
	}
    }
    if ($#possible == -1) {
	print "GUID Zero Audit: PASSED, there are no GUID zero players.\n";
	return 1;
    }
    &fisher_yates_shuffle(\@possible);


    my $total_tries = 5; # The total number of attempts to get an answer out of activision.
    my $read_timeout = 4; # Number of seconds to wait for activison to respond to a packet.
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

	socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp")) or die "Socket error: $!";

	$selecta = IO::Select->new();
	$selecta->add(\*SOCKET);
	
	while (($current_try++ < $total_tries) && ($still_waiting)) {
	    # Send the packet
	    $portaddr = sockaddr_in($port, $d_ip);
	    send(SOCKET, $send_message, 0, $portaddr) == length($send_message)
		or die "cannot send to $ip_address($port): $!\n\n";
	    
	    # Check to see if there is a response yet.
	    @ready = $selecta->can_read($read_timeout);
	    if (defined($ready[0])) {
		# Yes, the socket is ready.
		$portaddr = recv(SOCKET, $message, $maximum_lenth, 0)
		    or die "Socket error: recv: $!";
		# strip the 4 \xFF bytes at the begining.
		$message =~ s/^.{4}//;
		$got_response = 1;
		$still_waiting = 0;
	    } else {
		print "No response from $activision_master   Trying again...\n\n";
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
		    # $kick_reason = "using the same CD-Key from multiple computers.  One at a time, please.";
		    $kick_reason = "an ^4invalid CD-KEY^2.  Perhaps your CD-KEY is already in use?";
		}
		if (($dirtbag) && ($reason eq 'BANNED_CDKEY')) {
		    print"DIRTBAG: $name_by_slot{$slot} - $reason\n";
		    &rcon_command("say ^1$name_by_slot{$slot} ^2was kicked for $kick_reason");
		    sleep 1;
		    &rcon_command("tempbanclient $slot");
		    &log_to_file('logs/kick.log', "CD-KEY: $name_by_slot{$slot} was tempbanned for: $kick_reason");

		    my $ban_ip = 'undefined';
		    my $unban_time = $time + 28800;
		    if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
			$ban_ip = $ip_by_slot{$slot};
		    }
		    my $bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
		    $bans_sth->execute($time, $unban_time, $ban_ip, $guid_by_slot{$slot}, $name_by_slot{$slot}) 
			or &die_nice("Unable to do insert\n");

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

################

sub ftp_getNlines {
    my $bytes = ($ftp_lines+1) * 120; # guess how many bytes we have to download to get N lines
    
    my $keepGoing;
    my @data;
    my $length;
    do {
        my $actualBytes = &ftp_getNchars($bytes);
        open(FILE,$ftp_tmpFileName) || &die_nice("FTP: Could not open $ftp_tmpFileName");
        @data = <FILE>;
        close(FILE);
        unlink($ftp_tmpFileName);
	
        $length = $#data;

        $keepGoing = ($length<=$ftp_lines && $actualBytes==$bytes); #we want to download one extra line (to avoid truncation)
        $bytes = $bytes * 2; # get more bytes this time. TODO: could calculate average line length and use that
    } while ($keepGoing);

    $ftp_inbandSignaling && print "#START: (This is a hack to signal start of data in pipe)\n";
    # just print the last N lines
    my $startLine = $length-$ftp_lines;
    if ($startLine<0) { $startLine=0; }
    for (my $i=$startLine+1; $i<=$length; $i++) { # skip the first line, it will probably be truncated
        push @ftp_buffer, $data[$i];
    }
    @ftp_buffer = reverse @ftp_buffer;
    $ftp_inbandSignaling && print "#END: (This is a hack to signal end of data in pipe)\n";
    $ftp_inbandSignaling && &ftp_flushPipe;
}


# > ulimit -all
# ...
# pipe size          (512 bytes, -p) 8
# ...
sub ftp_flushPipe {
    print " "x(512*8);
    print "\n";
}

# get N bytes and store in tempfile, return number of bytes downloaded
sub ftp_getNchars {
    my ($bytes) = @_;
    my $type = $ftp->binary;
    my $size = $ftp->size($ftp_basename) || &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n");
    my $startPos = $size - $bytes;
    if ($startPos<0) { $startPos=0; $bytes=$size; } #file is smaller than requested number of bytes
    -e $ftp_tmpFileName && &die_nice("FTP: $ftp_tmpFileName exists");

    $ftp_verbose && warn "GET: $ftp_basename, $ftp_tmpFileName, $startPos\n";
    $ftp->get($ftp_basename,$ftp_tmpFileName,$startPos);

    return $bytes;
}

# 
sub ftp_get_line {
    my $line;
    if (!defined($ftp_buffer[0])) {
	$ftp_type = $ftp->binary;
        $ftp_currentEnd = $ftp->size($ftp_basename) || &die_nice("FTP: ERROR: $ftp_dirname/$ftp_basename does not exist or is empty\n");
	
        if ($ftp_currentEnd > $ftp_lastEnd) {
            $ftp_verbose && warn "FTP: SIZE $ftp_basename increased: ".($ftp_currentEnd-$ftp_lastEnd)." bytes\n";
            $ftp_verbose && warn "FTP: GET: $ftp_basename, $ftp_tmpFileName, $ftp_lastEnd\n";
            -e $ftp_tmpFileName && &die_nice("FTP: $ftp_tmpFileName exists");
	    while (!-e $ftp_tmpFileName) {
		$ftp->get($ftp_basename,$ftp_tmpFileName,$ftp_lastEnd);
	    }
            open(FILE,$ftp_tmpFileName) || &die_nice("FTP: Could not open $ftp_tmpFileName");
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
    } else { return undef; }
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
	# sleep 1;
	&rcon_command("say ^2 $description ^7 $is_was ^1ENABLED^7 by an admin.");
	# sleep 1;
    } elsif ($requested_state =~ /no|0|off|disable/i) {
        &log_to_file('logs/admin.log', "$description $is_was disabled by:  $name - GUID $guid");
        &rcon_command("set $attribute \"0\"");
        # sleep 1;
        &rcon_command("say ^2 $description ^7 $is_was ^1DISABLED^7 by an admin.");
        # sleep 1;
    } else {
	&log_to_file('logs/admin.log', "$description $is_was set to $requested_state:  $name - GUID $guid");
        &rcon_command("set $attribute \"$requested_state\"");
        # sleep 1;
        &rcon_command("say ^2 $description ^7 $is_was set to ^1set $requested_state^7 by an admin.");
        # sleep 1;

    }

}

sub mysql_fail {
    my $message = $_[0];
    print $message;
    $mysql_is_broken = 1;
    &mysql_repair();

}

sub mysql_repair {
    print "Next Repair Time in " . &duration(($time - $next_mysql_repair)) . "\n";
    print "REPAIR: $next_mysql_repair\n";
    print "  TIME: $time\n";
    if ($time > $next_mysql_repair) {
        $next_mysql_repair = $time + $mysql_repair_interval;
        print "Attempting to repair the mysql connection\n\n";
        $mysql_logging_dbh->disconnect();
        $mysql_logging_dbh = DBI->connect('dbi:mysql:' . $config->{'mysql_database'} . ':' . $config->{'mysql_hostname'},
                                          $config->{'mysql_username'}, $config->{'mysql_password'})
            or print "MYSQL LOGGING: Couldn't connect to mysql database: $DBI::errstr\n";
	$mysql_is_broken = 0;

    }    
}


sub update_name_by_slot {
    my $name = shift;
    my $slot = shift;
    if ((!defined($slot)) || ($slot !~ /^\-?\d+$/)) { &die_nice("invalid slot number passed to update_slot_by_name: $slot\n\n"); }
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
			if (($name_by_slot{$i} ne 'SLOT_EMPTY') && ($slot != $i)) {
			    
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
			&rcon_command("say ^1NAME THIEF DETECTED: ^3Slot \#^2 $slot ^3 was ^1perma^3banned for being a name stealing ^1BITCH!");
			# sleep 1;
			my $ban_ip = 'undefined';
			my $unban_time = 2125091758;
			if ($ip_by_slot{$slot} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
			    $ban_ip = $ip_by_slot{$slot};
			}
			&rcon_command("banclient $slot");
			sleep 1;
			&rcon_command("clientkick $slot");
			sleep 1;
			&log_to_file('logs/kick.log', "BAN: NAME_THIEF: $ban_ip / $guid_by_slot{$slot} was permanently for being a name thief:  $name / $name_by_slot{$slot} ");
			my $bans_sth = $bans_dbh->prepare("INSERT INTO bans VALUES (NULL, ?, ?, ?, ?, ?)");
			$bans_sth->execute($time, $unban_time, $ban_ip, $guid_by_slot{$slot}, '^1NAME STEALING BITCH!!!') or &die_nice("Unable to do insert\n");
						
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
    if (&flood_protection('friendlyfire', 60, $slot)) { return 1; }
    if ($state =~ /^(yes|1|on|enabled?)$/i) {
        &rcon_command("scr_friendlyfire 1");
	$friendly_fire = 1;
        # sleep 1;
        &rcon_command("say " . '" Админ ^1ВКЛЮЧИЛ ^7Огонь по союзникам. Будьте аккуратны, старайтесь не ранить своих товарищей по команде"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED by:  $name - GUID $guid");
    } elsif ($state =~ /^(off|0|no|disabled?)$/i) {
        &rcon_command("scr_friendlyfire 0");
        $friendly_fire = 0;
        # sleep 1;
        &rcon_command("say " . '" Админ ^2ВЫКЛЮЧИЛ ^7Огонь по союзникам"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was DISABLED by:  $name - GUID $guid");
    } elsif ($state =~ /^2$/i) {
        &rcon_command("scr_friendlyfire 2");
	$friendly_fire = 2;
        # sleep 1;
        &rcon_command("say " . '" Админ ^1ВКЛЮЧИЛ ^7Огонь по союзникам с рикошетным уроном"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED with reflective team damage by:  $name - GUID $guid");
    } elsif ($state =~ /^3$/i) {
        &rcon_command("scr_friendlyfire 3");
        $friendly_fire = 3;
        # sleep 1;
        &rcon_command("say " . '" Админ ^1ВКЛЮЧИЛ ^7Огонь по союзникам с совместным уроном"');
        &log_to_file('logs/admin.log', "!friendlyfire: friendly fire was ENABLED with shared team damage by:  $name - GUID $guid");
    } else {
        &rcon_command("say " . '" Неверное значение команды !friendlyfire. Доступны значения от 0 до 3"');
        # sleep 1;
    }
}
# END: &friendlyfire_command()

#BEGIN:  &make_affiliate_server_announcement()
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
	    if ($clients == 1) { $line = "" . '"^7кто то играет на"' . " ^7$hostname  ^7(^3$mapname^7/^5$gametype^7)\n" }
	    else { $line = "^1$clients " . '"^7игроков на"' . " ^7$hostname  ^7(^3$mapname^7/^5$gametype^7)\n"; }
	    if ($clients < $maxclients) {
		push @results, $line;
	    }
	}
    }

    if (defined($results[0])) {
	&rcon_command('say ' . $affiliate_server_prenouncements[int(rand() * $#affiliate_server_prenouncements)]);
	sleep 1;
	foreach $line (@results) {
	    &rcon_command("say $line");
	    # sleep 1;
	}
    }
}
# END: &make_affiliate_server_announcement()


# BEGIN: &get_server_info($ip_address)
sub get_server_info {
    # ripped from my getinfo.pl
    my $ip_address = shift;
    my $total_tries = 2; # The total number of attempts to get an answer out of the server.
    my $read_timeout = 2; # Number of seconds per attempt to wait for the response packet.
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

    if ($ip_address =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\:(\d{1,5})$/) {
	($ip_address,$port) = ($1,$2);
    }
    if ((!defined($ip_address)) || ($ip_address !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) {
	return "IP Address format error";
    }

    socket(SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp"))
    or return "Socket error: $!";

    my $send_message = "\xFF\xFF\xFF\xFFgetinfo xxx";

    $d_ip   = inet_aton($ip_address);

    my $selecta = IO::Select->new();
    $selecta->add(\*SOCKET);
    my @ready;

    while (($current_try++ < $total_tries) && ($still_waiting)) {
	# Send the packet
	$portaddr = sockaddr_in($port, $d_ip);
	send(SOCKET, $send_message, 0, $portaddr) == length($send_message)
	    or die "cannot send to $ip_address($port): $!\n\n";
	
	# Check to see if there is a response yet.
	@ready = $selecta->can_read($read_timeout);
	if (defined($ready[0])) {
	    # Yes, the socket is ready.
	    $portaddr = recv(SOCKET, $message, $maximum_lenth, 0)
		or die "Socket error: recv: $!";
	    # strip the 4 \xFF bytes at the begining.
	    $message =~ s/^.{4}//;
	    $got_response = 1;
	    $still_waiting = 0;
	} else {
	    print "No response from $ip_address:$port ...  Trying again...\n\n";
	}
    }
    if ($got_response) {
	if ($message =~ /infoResponse/) {
	    # print "Response from $ip_address:$port\n";
	    $message = substr($message,14,length($message));
	    my @parts = split(/\\/, $message);
	    my $value;
	    while (@parts) {
		$value = shift(@parts);
		$infohash{$value} = shift(@parts);
	    }
	    foreach (sort {$a cmp $b} keys %infohash) {
		$return_text .= "$_: " . $infohash{$_} . "\n";
	    }
	    # print "\n";
	}
    } else {
	print "\nERROR:\n\t$ip_address:$port is not currently responding to requests.\n";
	print "\n\tSorry.  Try again later.\n\n";
    }
    return $return_text;
}
# END: &get_server_info($ip_address)


# BEGIN: &broadcast_message($message)
sub broadcast_message {
    my $message = shift;
    if ((!defined($message)) || ($message !~ /./)) { return; }
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
	    $rcon = new KKrcon(
			       Host => $ip_address,
			       Port => $port,
			       Password => $password,
			       Type => 'old'
			       );
	    print $rcon->execute($message);
	    
	} else { print "WARNING: Invalid remote_server syntax: $config_val\n"; }
    }
    if ($num_servers == 0) { &rcon_command("say Sorry, there are no remote servers defined.  Check your nanny.cfg"); }
    elsif ($num_servers == 1) { &rcon_command("say OK, your message was broadcast to the other server."); }
    else { &rcon_command("say OK, your message was broadcast to $num_servers other servers"); }
}


# BEGIN: big_red_button_command()
sub big_red_button_command {
    my @matches = &matching_users('.');
    my $slot;
    &rcon_command("say " . '"О НЕТ!, он нажал ^1КРАСНУЮ КНОПКУ^7!!!!!!!"');
    sleep 1;
    foreach $slot (@matches) {
        &rcon_command("clientkick $slot");
	# sleep 1;
        &log_to_file('logs/kick.log', "!KICK: $name_by_slot{$slot} was kicked by $name - GUID $guid - via the !big red button command");
    }  
}

#BEGIN !rank


sub rank {

   if (&flood_protection('rank', 300, $slot)) { return 1; }

   my $rank_msg = "$name: ";
   my $kills = 1;

    $stats_sth = $stats_dbh->prepare("SELECT * FROM stats WHERE name=?");
    $stats_sth->execute($name) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
    @row = $stats_sth->fetchrow_array;
    if ((!$row[0]) && ($name ne &strip_color($name))) {
	$stats_sth->execute(&strip_color($name)) or &die_nice("Unable to execute query: $stats_dbh->errstr\n");
	@row = $stats_sth->fetchrow_array;
    }
    if ($row[0]) {
	$kills = $row[2];
	if ($row[2] > 99 && $row[2] < 500)
	{
	$rank_msg .= '"^7Твой ранг - ^1Опытный"' . "^7(^2$row[2]^7" . '"убийств)"' . "";
	}
	if ($row[2] > 9 && $row[2] < 50)
	{
	$rank_msg .= '"^7Твой ранг - ^1Новичок"' . "^7(^2$row[2]^7" . '"убийств)"' . "";
	}
	if ($row[2] > 499 && $row[2] < 1000)
	{
	$rank_msg .= '"^7Твой ранг - ^1Ветеран"' . "^7(^2$row[2]^7" . '"убийств)"' . "";
	}
	if ($row[2] > 999)
	{
	$rank_msg .= '"^7Твой ранг - ^1Мастер"' . "^7(^2$row[2]^7" . '"убийств)"' . "";
	}
	if ($row[2] < 9)
	{
	$rank_msg .= '"^7Твой ранг - ^1Гость"' . "^7(^2$row[2]^7" . '"убийств)"' . "";
	}
	if ($row[2] > 49 && $row[2] < 100)
	{
	$rank_msg .= '"^7Твой ранг - ^1Бывалый"' . "^7(^2$row[2]^7" . '"убийств)"' . "";
	}
    }
    &rcon_command("say $rank_msg");
    print "$rank_msg\n"; 
    # sleep 1; 
}