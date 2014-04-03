init()
{
	thread chkBashMode();
}

chkBashMode()
{
	level endon("killModThread");

	for (;;)
	{
		wait 0.1;

		_b = svr\utils::cvardef("bash_mode", 0, 0, 1, "int");

		if (_b)
		{
			if (!isDefined(game["bashModeOn"]))
			{
				_m = svr\utils::cvardef("bash_on_msg", "", "", "", "string");
				if (_m != "")	  iprintlnbold(_m);
                        	//iprintlnBold("^7BASH MODE - ^1ON");
			}
			setBashMode(true);
		}
		else
		{
			if (isDefined(game["bashModeOn"]))
			{
				_m = svr\utils::cvardef("bash_off_msg", "", "", "", "string");
				if (_m != "")	  iprintlnbold(_m);
                        	//iprintlnBold("^7BASH MODE - ^2OFF");
							
				setBashMode(false);
			}
		}
	}
}

setBashMode(enable)
{
	level endon("killModThread");

	players = getentarray("player", "classname");

	for (i = 0; i<players.size; i++)
	{
		_p = players[i];

		if (enable)
		{
			game["bashModeOn"] = true;

			if (_p getWeaponSlotWeapon("primary") != "none")
			{
				//iprintln("primary is: " + _p getWeaponSlotWeapon("primary"));
				_p setWeaponSlotAmmo("primary", 0);
				_p setWeaponSlotClipAmmo("primary", 0);
			}
			if (_p getWeaponSlotWeapon("primaryb") != "none")
			{
				//iprintln("primaryb is: " + _p getWeaponSlotWeapon("primaryb"));
				_p setWeaponSlotAmmo("primaryb", 0);
				_p setWeaponSlotClipAmmo("primaryb", 0);
			}

			_p takeWeapon("frag_grenade_american_mp");
			_p takeWeapon("frag_grenade_british_mp");
			_p takeWeapon("frag_grenade_russian_mp");
			_p takeWeapon("frag_grenade_german_mp");
			_p takeWeapon("smoke_grenade_american_mp");
			_p takeWeapon("smoke_grenade_british_mp");
			_p takeWeapon("smoke_grenade_russian_mp");
			_p takeWeapon("smoke_grenade_german_mp");
		}
		else
		{
			game["bashModeOn"] = undefined;

			_w = _p getWeaponSlotWeapon("primary");
			if (_w != "none")
			{
				//iprintln("primary is: " + _w);
				_p setweaponslotclipammo("primary", svr\utils::getFullClipAmmo(_w));
				_p giveMaxAmmo(_p getWeaponSlotWeapon("primary"));
			}

			_w = _p getWeaponSlotWeapon("primaryb");
			if (_w != "none")
			{
				//iprintln("primaryb is: " + _w);
				_p setweaponslotclipammo("primaryb", svr\utils::getFullClipAmmo(_w));
				_p giveMaxAmmo(_p getWeaponSlotWeapon("primaryb"));
			}

			_p maps\mp\gametypes\_weapons::giveGrenades();

		}
	}
}
