cvardef(varname, vardefault, min, max, type)
{
	mapname = getcvar("mapname");		// "mp_dawnville", "mp_rocket", etc.
	gametype = getcvar("g_gametype");	// "tdm", "bel", etc.
	mapgt = gametype + "_" + mapname;	// "tdm_mp_dawnville"

	tempvar = varname + "_" + gametype;	// i.e., scr_teambalance becomes scr_teambalance_tdm
	if(getcvar(tempvar) != "") 		// if the gametype override is being used
		varname = tempvar; 		// use the gametype override instead of the standard variable

	tempvar = varname + "_" + mapname;	// i.e., scr_teambalance becomes scr_teambalance_mp_dawnville
	if(getcvar(tempvar) != "")		// if the map override is being used
		varname = tempvar;		// use the map override instead of the standard variable

	tempvar = varname + "_" + mapgt;	// i.e., scr_teambalance becomes scr_teambalance_mp_dawnville_tdm
	if(getcvar(tempvar) != "")		// if the map override is being used
		varname = tempvar;		// use the map override instead of the standard variable

	// get the variable's definition
	switch(type)
	{
		case "int":
			if(getcvar(varname) == "")		// if the cvar is blank
				definition = vardefault;	// set the default
			else
				definition = getcvarint(varname);
			break;
		case "float":
			if(getcvar(varname) == "")		// if the cvar is blank
				definition = vardefault;	// set the default
			else
				definition = getcvarfloat(varname);
			break;
		case "string":
		default:
			if(getcvar(varname) == "")		// if the cvar is blank
				definition = vardefault;	// set the default
			else
				definition = getcvar(varname);
			break;
	}

	// if it's a number, with a minimum, that violates the parameter
	if((type == "int" || type == "float") && min != 0 && definition < min)
		definition = min;

	// if it's a number, with a maximum, that violates the parameter
	if((type == "int" || type == "float") && max != 0 && definition > max)
		definition = max;

	return definition;
}

getTeam(team)
{
	if (self.sessionstate == "playing" && self.sessionteam == "none")
		return self.pers["team"];
	else if (self.sessionstate == "playing" && self.sessionteam != "none")
		return self.sessionteam;
	else
		return undefined;
}

debug(why, where, who)
{
	if (!isDefined(why) || !isDefined(where))
		return;

	_d = level.mod + why + " , " + where;

	if (isDefined(who))
		_d = _d + " , " + who;

	logprint(_d + "\n");

	if (level.debugSvr == 3)
		iprintln(_d);
	else if (level.debugSvr == 2 && isDefined(who))
		iprintln(_d);
}

// from CoDaM mod by [MC] Hammer
isNumeric( str )
{
//	debug( 98, "isNumeric:: |", str, "|" );

	if ( !isdefined( str ) || ( str == "" ) )
		return ( false );

	str += "";
	for ( i = 0; i < str.size; i++ )
		switch ( str[ i ] )
		{
		  case "0": case "1": case "2": case "3": case "4":
		  case "5": case "6": case "7": case "8": case "9":
		  	break;
		  default:
		  	return ( false );
		}

	return ( true );
}

restartRound(spawn)
{
	level.starttime = getTime();

	if (isDefined(level.clock))
		level.clock setTimer(level.timelimit * 60);

	if (level.teamplay && level.gt != "bel")
	{
		game["alliedscore"] = 0;
		setTeamScore("allies", game["alliedscore"]);
		game["axisscore"] = 0;
		setTeamScore("axis", game["axisscore"]);
	}

	players = getentarray("player", "classname");
	for (i = 0; i < players.size; i++)
	{
		_p = players[i];

		_p.score = 0;
		_p.deaths = 0;
	}

	map_restart(true);
}
/*
		if (spawn && _p.sessionstate == "playing" && level.gt != "bel")
		{
			_p notify("killModThread");
			wait .05;

			_p [[level.spawnplayer]]();
		}
		else
		{
			if (_p.sessionstate == "playing")
			{
				_p.maxhealth = 100;
				_p.health = _p.maxhealth;

				_w = _p getWeaponSlotWeapon("primary");
				if (_w != "none")
				{
					//iprintln("primary is: " + _w);
					_p setweaponslotclipammo("primary", getFullClipAmmo(_w));
					_p giveMaxAmmo(_p getweaponslotweapon("primary"));
				}

				_w = _p getWeaponSlotWeapon("primaryb");
				if (_w != "none")
				{
					//iprintln("primaryb is: " + _w);
					_p setweaponslotclipammo("primaryb", getFullClipAmmo(_w));
					_p giveMaxAmmo(_p getweaponslotweapon("primaryb"));
				}

				_p maps\mp\gametypes\_weapons::giveGrenades();
			}
		}
	}
}
*/
getFullClipAmmo(_w)
{
	switch (_w)
	{

	// -- Snipers
		case "springfield_mp":		return 5;
		case "enfield_scope_mp":	return 10;
		case "mosin_nagant_sniper_mp":	return 5;
		case "kar98k_sniper_mp":	return 5;

	// -- Bolt-action
		case "enfield_mp":		return 10;
		case "mosin_nagant_mp":		return 5;
		case "kar98k_mp":		return 5;

	// -- Semi-auto
		case "m1carbine_mp":	return 15;
		case "m1garand_mp":	return 8;
		case "SVT40_mp":	return 10;
		case "g43_mp":		return 10;

	// -- Machineguns
		case "bar_mp":		return 20;
		case "bren_mp":		return 30;
		case "mp44_mp":		return 30;

	// -- Pussyguns
		case "thompson_mp":	return 30;
		case "greasegun_mp":	return 32;
		case "sten_mp":		return 32;
		case "PPS42_mp":	return 35;
		case "ppsh_mp":		return 71;
		case "mp40_mp":		return 32;

	// -- Pistols
		case "colt_mp":		return 7;
		case "webley_mp":	return 6;
		case "TT30_mp":		return 8;
		case "luger_mp":	return 8;

	// -- Misc/other
		case "shotgun_mp":	return 6;

		default:
		   	return 0;
	}
		
	return 0;
}

specPermissions()
{
	return;
}

spawnSpectator(origin, angles)
{
	gt = getCvar("g_gametype");

	if (isAlive(self))
	{
		self.switching_teams = true;
		self.joining_team = "spectator";
		self.leaving_team = self.pers["team"];
		self suicide();
	}

	self.pers["team"] = "spectator";
	self.pers["weapon"] = undefined;
	self.pers["weapon1"] = undefined;
	self.pers["weapon2"] = undefined;
	self.pers["spawnweapon"] = undefined;
	self.pers["savedmodel"] = undefined;

	self.sessionteam = "spectator";
	self setClientCvar("ui_allow_weaponchange", "0");

	if (gt == "hq")
		self thread maps\mp\gametypes\hq::updateTimer();

	self notify("spawned");
	self notify("end_respawn");

	resettimeout();

	// Stop shellshock and rumble
	self stopShellshock();
	self stoprumble("damage_heavy");

	self.sessionstate = "spectator";
	self.spectatorclient = -1;
	self.archivetime = 0;
	self.psoffsettime = 0;
	self.friendlydamage = undefined;

	if (self.pers["team"] == "spectator")
		self.statusicon = "";

	if (!isdefined(self.skip_setspectatepermissions) && gt != "dm")
		maps\mp\gametypes\_spectating::setSpectatePermissions();

	if (isdefined(origin) && isdefined(angles))
		self spawn(origin, angles);
	else
	{
 		spawnpointname = "mp_global_intermission";
		spawnpoints = getentarray(spawnpointname, "classname");
		spawnpoint = maps\mp\gametypes\_spawnlogic::getSpawnpoint_Random(spawnpoints);

		if (isdefined(spawnpoint))
			self spawn(spawnpoint.origin, spawnpoint.angles);
		else
			maps\mp\_utility::error("NO " + spawnpointname + " SPAWNPOINTS IN MAP");
	}

	if (gt == "sd")
	{
		level maps\mp\gametypes\sd::updateTeamStatus();
		self.usedweapons = false;
	}
	else if (gt == "hq")
		level maps\mp\gametypes\hq::hq_removeall_hudelems(self);

	self setClientCvar("cg_objectiveText", "");
	self setClientCvar("g_scriptMainMenu", game["menu_ingame"]);

	self notify("joined_spectators");
	self notify("end_respawn");
}

getScores(_t)
{
	if (!isDefined(_t))
		return;

	if (_t == "teamscore")
	{
		if (level.roundbased)
		{
			level.aScore = game["alliedscore"];
			level.xScore = game["axisscore"];
		}
		else if (!(level.gt == "bel" || level.gt == "dm"))
		{
			level.aScore = getTeamScore("allies");
			level.xScore = getTeamScore("axis");
		}
		return;
	}

	level.highScoreName = undefined;
	level.highScoreVal = undefined;
	_n = undefined;
	_s = 0;

	players = getentarray("player", "classname");
	for (i = 0; i < players.size; i++)
	{
		_p = players[i];

		if (_t == "score")
			_p.pers["score"] = _p.score;
		else if (_t == "deaths")
			_p.pers["deaths"] = _p.deaths;

		if (_p.pers[_t] >= _s)
		{
			_n = _p.name;
			_s = _p.pers[_t];
		}
	}

	if (isDefined(_n) && _s > 0)
	{
		level.highscoreName = _n;
		level.highscoreVal = _s;
	}
}

