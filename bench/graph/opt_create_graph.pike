#!/usr/bin/env pike

#define USE_SCREENSHOTS 0
#define VERBOSE 0

mapping runspecifics = ([]);
void verify_runspecific(string name, string|int value)
{
    if(value == "")
	return;

    // Allow for some very similar systems to pollute the pool
    if(value == "ProLiant SL230s G8") {
	if(VERBOSE > 1)
	    werror("NOTE: upcasting systemtype\n");
	value = "ProLiant SL250s G8";
    }

    if(!runspecifics[name]) {
	runspecifics[name] = value;
    } else {
	if(runspecifics[name] != value) {
	    if(name == "systemram" && (int)value > 24) {
		// Allow RAM missmatches as long as there is enough of it
		if(VERBOSE > 1)
		    werror("WARNING: %s missmatch, %O != %O\n", name, value, runspecifics[name]);
	    } else {
		exit(1, "FATAL: %s missmatch, %O != %O\n",
		     name, value, runspecifics[name]);
	    }
	}
    }
}

//FIXME: Get all details from the files
// Still in use:
//    res->mameversion
mapping parse_filename(string filename)
{
    mapping res = ([]);
    filename = basename(filename);

    //example: 1943-xeon_x5570-0.212-gcc5-O2.result.1
    if(sscanf(filename, "%s-%s-0.%d-%s-%s.result.%d",
	      res->game, res->shortname, res->mameversion, res->compiler, res->opt_id, res->runnr) == 6) {
	return res;
    }
    //example: 1943-xeon_x5570-0.212-gcc5.result.1
    if(sscanf(filename, "%s-%s-0.%d-%s.result.%d",
	      res->game, res->shortname, res->mameversion, res->compiler, res->runnr) == 5) {
	return res;
    }

    exit(1, "FATAL: Unable to parse filename '%s'\n", filename);
}

mapping test_types = ([]); // Keep track of which types have been seen
mapping parse_result(string filename, string opt_id)
{
    object resultlines = Stdio.File(filename)->line_iterator();
    mapping res = ([]);
    string current_test_type;
    foreach(resultlines; int lnr; string line) {
	if(VERBOSE > 2)
	    werror("line: '%s'\n", line);
	switch(lnr) {
	case 0:
	    if(sscanf(line, "Name:%*[ ]Description:") != 1) {
		werror("WARNING: Failed to parse line %d '%s' in \n%s\n",
		       lnr, line, filename);
		return 0;
	    }
	    break;
	case 1:
	    int matches = sscanf(line, "%s%*[ ]\"%s\"", res->game, res->game_desc);
	    if(matches != 3) {
		werror("WARNING: Failed to parse line %d '%s' in \n%s\n",
		       lnr, line, filename);
		return 0;
	    }
	    break;
	default:
	    int temp;
	    string throttled;
	    if(sscanf(line, "Before run: %d throttled=%s",
		      int temp, string throttled) == 2) {
		res->temp_before = temp;
		res->throttled_before = throttled;
		//NOTE: I'm not really interested in undervoltage events right now
		if(res->throttled_before == "0x50000")
		    res->throttled_before = "0x0";
	    }
	    if(sscanf(line, "After run: %d throttled=%s",
		      int temp, string throttled) == 2) {
		res->temp_after = temp;
		res->throttled_after = throttled;
		//NOTE: I'm not really interested in undervoltage events right now
		if(res->throttled_after == "0x50000")
		    res->throttled_after = "0x0";
	    }
	    if(line == "Running real emulation benchmark") {
		current_test_type = "real";
		test_types[current_test_type] = true;
		res->real = ([]);
	    }
	    if(line == "Running built in benchmark") {
		current_test_type = "bench";
		test_types[current_test_type] = true;
		res->bench = ([]);
	    }
	    if(sscanf(line, "Average speed: %f%% (%d seconds)",
		      float speed, int runtime) == 2) {
		res[current_test_type]->percent = speed;
		res[current_test_type]->runtime = runtime;

		// FIXME: Remove this
		if(speed == 0)
		    exit(1, "FATAL: speed is 0 in %O:%O\n",
			 speed, filename, current_test_type);
		
		if(res[current_test_type]->runtime != 89)
		    exit(1, "FATAL: test runtime in '%s' is not 89s!", filename);
	    }
	    if(line == "Fatal error: Required files are missing, the machine cannot be run.")
	    {
		res[current_test_type]->failtype = "missing files";
	    }
	    if(sscanf(line, "CC: %s", string compiler) == 1) {
		verify_runspecific("compiler", compiler);
	    }
	    if(sscanf(line, "OPTIMIZE: %s", string optimize) == 1) {
		res->optimize = optimize; //TODO, overwritten and not used
	    }
	    if(sscanf(line, "ARCHOPTS: %s", string archopts) == 1) {
		res->archopts = archopts; //TODO, overwritten and not used
	    }
	    if(sscanf(line, "Optimization ID: %s", string _opt_id) == 1) {
		if(_opt_id == "") // Default -O3
		    _opt_id = 0;
		
		res->opt_id = _opt_id;
		verify_runspecific("opt_id", opt_id);
	    }
	    if(sscanf(line, "Mame: %s", string version) == 1) {
		res->mameversion = version;
		// FIXME: hardcoded to skip older than 0.202
		// comparison happens to work becuase no results are <0.100
		if( (float)version < 0.202 ) {
		    if(VERBOSE > 1)
			werror("skipping: %O %O %O\n", 
			       version, (float)version, res->game);
		    return 0;
		}
	    }
	    if(sscanf(line, "System: %s", string id) == 1) {
		verify_runspecific("systemid", id);
	    }
	    if(sscanf(line, "System type: %s", string systemtype) == 1) {
		verify_runspecific("systemtype", systemtype);
	    }
	    if(sscanf(line, "System RAM: %sG", string gibs) == 1) {
		verify_runspecific("systemram", gibs);
	    }
	    if(sscanf(line, "Num CPU: %d", int sockets) == 1) {
		verify_runspecific("sockets", sockets);
	    }
	    break;
	}
    }
    // FIXME: Only needed for earlier files that did no record compiler and mame version
    // Remove this
    if(!res->mameversion) {
	mapping fileinfo = parse_filename(filename);
	res->mameversion = "0."+ fileinfo->mameversion;
	if(!res->compiler)
	    res->compiler = fileinfo->compiler;
    }

    // FIXME: Hacks for non-RPi
    if(!res->throttled_before)
	res->throttled_before="0x0";
    if(!res->throttled_after)
	res->throttled_after="0x0";
    return res;
}

mapping missingroms = ([]); // Redundant, for easy access
string create_table(mapping all_results, string type)
{
    //Table view
    mapping(string:array) tdata = ([
	"cols": ({}),
	"rows": ({}),
    ]);

    tdata->cols += ({ (["id":"", "label":"Game",   "pattern":"", "type":"string"]),
		      (["id":"", "label":"Driver", "pattern":"", "type":"string"]),
    });
    array all_versions = ({}); //Games might not have results for all
			       //version, so save a complete list
    foreach(sort(indices(all_results)), string version) {
	all_versions += ({ version });
	// TODO: Why did I choose number? Maybe change to string
	tdata->cols += ({ (["id":"","label":version, "pattern":"","type":"number"]) });
    }
    tdata->cols += ({ (["id":"", "label":"Game identifier", "pattern":"", "type":"string"]),
		      (["id":"", "label":"notes",           "pattern":"", "type":"string"]),
    });

    // Rebuild data into game -> versioninfo
    mapping gamedata = ([]);
    foreach(all_results; string version; mapping games) {
	foreach(indices(games), string game) {
	    gamedata[game] += ([ version: games[game] ]);
	}
    }
    //    werror("gamedata: %O\n", gamedata);

    foreach(sort(indices(gamedata)), string game) {
	array vbenches = ({});
	string game_desc;
	// foreach(sort(indices(gamedata[game])), string version) {
	foreach(all_versions, string version) {
	    //werror("gdg->v: %O\n", gamedata[game][version]);
	    //werror("v: %O\n", version);
	    if(gamedata[game][version]) {
		game_desc = gamedata[game][version]->game_desc; // Keep the newest one
		if( !gamedata[game][version][type] ||
		    !gamedata[game][version][type]->percent )
		{
		    // There is and entry, but it lacks data due to crash or timeout
		    string style = "color:#006600; background-color:grey;";
		    if(gamedata[game][version][type] &&
		       gamedata[game][version][type]->failtype == "missing files") {
			// Per type fail for this is redundant, but doesn't hurt
			style = "color:#006600; background-color:red;";
			if(!missingroms[game])
			    missingroms[game] = ({});
			missingroms[game] += ({ version });
			werror("%s %s is missing files\n", game, version);
		    }
		    //TODO: Using Var.Null breaks encoding
		    vbenches += ({ (["v":"null", "p":([ "style": style ]) ]) });
		} else {
		    // Regular good entry (possibly throttled)
		    float percent = gamedata[game][version][type]->percent;
		    if( gamedata[game][version]->throttled_before != "0x0"
			|| gamedata[game][version]->throttled_after != "0x0" )
		    {
			vbenches += ({ (["v":percent, "p":(["style": "background-color:orange;" ]) ]) });
		    } else {
			vbenches += ({ (["v":percent]) });
		    }
		}
	    } else {
		// There is no entry of this game for this version
		vbenches += ({ (["v":"null" ]) });
	    }
	}

	mapping note;
	string note_text;
	// Notes about game are hardcoded here
	// FIXME: Move this to a separate file
	switch(game) {
	case "cubeqst":
	    note_text = "†"; break;
	default:
	    note_text = ""; break;
	}

	// NOTE: Requires create_chart to have been run first
	if(stats->games[game] && stats->games[game][type]) {
	    note_text += sprintf(" (%d data points)", stats->games[game][type]->samples);
	}

	note = (["v":note_text]);
	
	tdata->rows += ({
	    (["c": ({
		(["v":game]),
		(["v":get_driver(game)]),
		@vbenches,
		(["v":game_desc]),
		note
	    }) ])
	});
    }

    // werror("DEBUG encoding this:\n%O\n", tdata);
    
    string res = "var jsonData = ";
    res += Standards.JSON.encode(tdata,
	       Standards.JSON.HUMAN_READABLE | Standards.JSON.PIKE_CANONICAL);
    res = replace(res, "\"v\": \"null\"", "\"v\": null"); //FIXME: kludge
    return res;
}

float get_speed(mapping game)
{
    if(!game)
	return 0;
    return game->percent;
}

//! Return the relative change in speed compared to the nearest
//! previous data point
string get_speed_diff(mapping gamedata, string game, string version, string type)
{
    float speed = get_speed(gamedata[game][version][type]);

    foreach(reverse(sort(indices(gamedata[game]))), string old_ver) {
	if((float)old_ver >= (float)version) {
	    //	    werror("Skipping %O\n", old_ver);
	    continue;
	}
	float old_speed = get_speed(gamedata[game][old_ver][type]);
	if(old_speed) {
	    float diff = speed - old_speed;
	    float percent_change = (diff / old_speed)*100;
	    constant cutoff = 2; // Don't clutter annotations with small changes
	    if(abs(percent_change) < cutoff) {
		return "null";
	    } else {
		string n = (string)(int)round(percent_change);
		if(percent_change > 0)
		    return "+"+n;
		else
		    return n;
	    }
	}
    }

    return "";
}

mapping stats = ([ "games":([]) ]);
// TODO: clean up both create_* functions, they contain a lot of cut'n'paste
string create_chart(mapping all_results, string type)
{
    // Linechart view
    mapping(string:array) cdata = ([
	"cols": ({}),
	"rows": ({}),
    ]);

    // Rebuild data into game -> versioninfo
    mapping gamedata = ([]);
    foreach(all_results; string version; mapping games) {
	foreach(indices(games), string game) {
	    gamedata[game] += ([ version: games[game] ]);
	}
    }
    
    cdata->cols += ({ (["id":"", "label":"Version", "pattern":"", "type":"number"]) });
    array all_versions = ({}); //Games might not have results for all
			       //version, so same a complete list
    all_versions = sort(indices(all_results));

    foreach(sort(indices(gamedata)), string game) {
	cdata->cols += ({ (["id":"","label":game, "pattern":"","type":"number"]) });
	// The next two columns are for min and max value
	cdata->cols += ({ (["id":"","label":"","pattern":"","type":"number",
			    "p":(["role":"interval"]) ]) });
	cdata->cols += ({ (["id":"","label":"","pattern":"","type":"number",
			    "p":(["role":"interval"]) ]) });
	cdata->cols += ({ (["id":"","label":"","pattern":"","type":"string",
			    "p":(["role":"tooltip", "html":true]) ]) });
	cdata->cols += ({ (["id":"","label":"","pattern":"","type":"string",
			    "p":(["role":"annotation", "html":true]) ]) });
    }

    foreach(all_versions, string version) {
	array vbenches = ({});
	string game_desc;
	foreach(sort(indices(gamedata)), string game) {
	    if(gamedata[game][version]) {
		game_desc = gamedata[game][version]->game_desc; // Keep the newest one
		if( !gamedata[game][version][type] ||
		    !gamedata[game][version][type]->percent )
		{
		    stats->crashed += 1;
		    // There is an entry, but it lacks data due to crash or timeout
		    //TODO: Using Var.Null breaks encoding
		    vbenches += ({ (["v":"null" ]) });
		} else {
		    // Regular good entry

		    // The Google Charts chart type will multiply the
		    // value by 100 if it's told it's a percentage
		    // value, so pre-devide it.
		    float percent = gamedata[game][version][type]->percent;
		    if(gamedata[game][version]->throttled_before != "0x0" ||
		       gamedata[game][version]->throttled_after != "0x0") {
			stats->throttled += 1;
			vbenches += ({ (["v":percent/100 ]) });
		    } else {
			stats->good += 1;
			vbenches += ({ (["v":percent/100]) });
		    }
		}
	    } else {
		// There is no entry of this game for this version
		stats->missing += 1;
		vbenches += ({ (["v":"null" ]) });
	    }
	    // tooltip that will be shown when hovering over a datapoint
	    //	    werror("%O %O\n", version, game);
	    string tooltip = sprintf("%s <b>%s</b><br>\n", version, game);
	    if(!stats->games[game])
		stats->games[game]=([]);
	    if(!stats->games[game][type])
		stats->games[game][type]=([]);
	    // FIXME: These depth of these tests are here for a
	    // reason, but something is wrong when they are
	    // needed. Examine what and remove
	    string annotation = "null";
	    if(gamedata[game][version] &&
	       gamedata[game][version][type] &&
	       gamedata[game][version][type]->multi_percent) {
		annotation = get_speed_diff(gamedata, game, version, type);
		// Handles multiple runs. Straight average for now
		// NOTE: copy_value if the order ever becomes important
		array speeds = gamedata[game][version][type]->multi_percent;
		float min_percent = sort(speeds)[0];
		float max_percent = sort(speeds)[-1];
		vbenches += ({ (["v":min_percent/100]) });
		vbenches += ({ (["v":max_percent/100]) });
		tooltip += sprintf("<table><tr><td align=right>average:</td><td>%.1f%%</td></tr>"
				   "<tr><td align=right>min:</td><td>%.1f%%</td></tr>"
				   "<tr><td align=right>max:</td><td>%.1f%%</td></tr></table>"
				   "(%d datapoins)<br>",
				   gamedata[game][version][type]->percent,
				   min_percent,
				   max_percent,
				   sizeof(speeds));
		stats->games[game][type]->samples += sizeof(speeds);
	    } else {
		vbenches += ({ (["v":"null"]) });
		vbenches += ({ (["v":"null"]) });
		if(gamedata[game][version] &&
		   gamedata[game][version][type] &&
		   gamedata[game][version][type]->percent) {
		    annotation = get_speed_diff(gamedata, game, version, type);
		    tooltip += sprintf("%.1f%%<br>(one datapoint)<br>",
				       gamedata[game][version][type]->percent);
		}
		stats->games[game][type]->samples++;
	    }
	    if(USE_SCREENSHOTS) {
		string image = sprintf("screenshots/%s-%s.png", game, version);
		if(file_stat("output/"+image)) {
		    tooltip += sprintf("<img src=%s>", image);
		} else {
		    werror("Image %O not found\n", image);
		}
	    }
	    vbenches += ({ (["v":tooltip]) });
	    vbenches += ({ (["v":annotation]) });
	}

	cdata->rows += ({
	    (["c": ({
		(["v":version]),
		@vbenches
	    }) ])
	});
    }

    // werror("DEBUG encoding this:\n%O\n", cdata);
    
    string res = "var jsonChart = ";
    res += Standards.JSON.encode(cdata,
	       Standards.JSON.HUMAN_READABLE | Standards.JSON.PIKE_CANONICAL);
    res = replace(res, "\"v\": \"null\"", "\"v\": null"); //FIXME: kludge
    return res;
}

mapping(string:string) drivercache = ([]);
string get_driver(string game)
{
    // FIXME: Part of the optimization alts hack
    game = (game/" ")[0];

    if(drivercache[game])
	return drivercache[game];
    
    string exe = "../../../arch/x86_64-64/stored-mames/mame0214-gcc8-24d07a1/mame64";
    mapping res = Process.run( ({ exe, "-listsource", game }) );
    if(res->exitcode)
	exit(1, "FATAL: Failed to get driver for %s\nstdout: %O\nstderr: %O",
	     game, res->stdout, res->stderr);
    sscanf(res->stdout, game+"%*[ ]%s.cpp", string driver);
    drivercache[game] = driver;
    return driver;
}

// string create_ranges( array(float) versions ) {
//     versions = sort(versions);
//     array(array(float)) ranges = ({});
//     float cur_rangestart = versions[0];
//     float cur_rangeend;
//     array(float) cur_range;

//     if(sizeof(versions) == 1)
// 	return sprintf("%3f", versions);
	
//     for(int i=1; i<sizeof(versions); i++) {
// 	if( i < sizeof(versions)-2 ) {
// 	    // we can check next
// 	} else {
// 	    // Time to close off the last range
// 	    ranges += ({ ({ cur_rangestart, cur_rangeend }) });
// 	    continue;
// 	}
// 	if( versions[i] - cur_rangestart == 0.1 ) {
// 	    cur_rangeend = versions[i];
// 	} else {
// 	    ranges += ({ ({ cur_rangestart, cur_rangeend }) });
// 	}
//     }
// }

// string missing_roms() {
//     mapping missingroms = ([]); // Redundant, for easy access
//     string res = "";
//     foreach(missingroms; string game; array versions) {
// 	res += game +" "+ create_ranges( (array(float))versions ) +" is missing files\n";
//     }
// }

int main(int argc, array argv)
{
    if(argc != 3) {
	exit(1, "Usage: opt_create_graph.pike <game name> <system shortname>\n"
	     "Examples:\n"
	     "    ./create_graph.pike tekken rpi4_1.75\n"
	     "    ./create_graph.pike starwars xeon_x5570\n"
	     "    ./create_graph.pike 1943 xeon_e5_2660\n");
    }
    // TODO: Use the argument parser
    string listfile = argv[1]; //FIXME: This is the game name for this hack
    string shortname = argv[2];
    string opt_id = listfile; // FIXME: Just used for benchmark filename in this hack
    string result_base = "../benchresult/"+ shortname +"/";

    werror("Processing %O\n", listfile);

    array result_files = get_dir(result_base);
    mapping all_results = ([]);
    array games = ({ listfile }); // TODO: More than one game per graph?
    foreach(games; int lnr; string game) {
	if(game[0..0] == "#")
	    continue; // Skip comments

	// The result files are a bit free form because they are
	// partly the output from the mame binary
	foreach( glob(game+"-*", result_files), string resultfile ) {
	    string filename = result_base + resultfile;
	    mapping result = parse_result(filename, opt_id);
	    if(!result) // The opt_id didn't match or we purposly avoid version
		continue;

	    // werror("result: %O\n", result);
	    
	    string ver = result->mameversion;
	    if(! all_results[ver])
		all_results[ver] = ([]);

	    // FIXME: quick hack where diffrent compiler options gets
	    // added as diffrent games
	    if(result->opt_id)
		game = game +" "+ result->opt_id;
	    else
		game = game +" O3";

	    // If there is more than one test of the same game/version, average them
	    //FIXME: This ignores every parameter except the speed value
	    if(all_results[ver][game]) {
		foreach( indices(test_types), string type) {
		    if(all_results[ver][game][type]) {
			if(result[type] && result[type]->percent) {
			    if(!all_results[ver][game][type]->multi_percent) {
				if(all_results[ver][game][type]->percent) {
				    all_results[ver][game][type]->multi_percent = ({all_results[ver][game][type]->percent});
				} else {
				    all_results[ver][game][type]->multi_percent = ({});
				}
			    }
			    all_results[ver][game][type]->multi_percent += ({ result[type]->percent });
			    all_results[ver][game][type]->percent = `+(@all_results[ver][game][type]->multi_percent) / sizeof(all_results[ver][game][type]->multi_percent);
			}
		    } else {
			if(result[type])
			    all_results[ver][game][type] = result[type];
		    }
		}
	    } else {
		all_results[ver][game] = result;
	    }
	    //werror("all_results[%s][%s]: %O\n", ver, game, all_results[ver][game]);
	    // FIXME: quick hack where diffrent compiler options gets
	    // added as diffrent games
	    game = (game/" ")[0];
	}
    }

    // werror("all_results: %O\n", all_results);
    
    // FIXME: write down more data in the results files so the hardcoding can stop
    foreach( indices(test_types), string type) {
	// create_chart has the side effect of setting up some
	// statistics needed for create_table, so the ordering is
	// important
	string chart_data = create_chart(all_results, type);
	string table_data = create_table(all_results, type);
	if(VERBOSE > 1) {
	   werror("DEBUG table_data:\n%s\n", table_data);
	   werror("DEBUG chart_data:\n%s\n", chart_data);
	}

	string flags;
	switch(type) {
	case "bench":
	    flags="-bench 90";
	    break;
	case "real":
	    flags="-str 90 -nothrottle";
	    break;
	default:
	    exit(1, "FATAL: Unknown benchmark type %O", type);
	}


	// werror("runspecifics: %O\n", runspecifics);

	string cpus = "";
	if(runspecifics->sockets > 1)
	    cpus = sprintf("%d x ", runspecifics->sockets);

	string system_desc, system_extra_desc="";
	switch(runspecifics->systemid) {
	case "xeon_x5570": //crux
	    system_desc = cpus +"Xeon X5570, "+ runspecifics->systemram +"G RAM, @2.93GHz. WARNING: machine not idle, only for testing, not usable as benchmark!";
	    break;
	case "xeon_e5_2660": //analysator
	    //Nodes have a minimum of 32G, hardcode it
	    system_desc = cpus +"Xeon E5-2660, 32G+ RAM, @2.20GHz";
	    break;
	case "rpi4_1.75":
	    system_desc = "RPi4, "+ runspecifics->systemram +"G RAM, overclocked to 1.75GHz";
	    system_extra_desc = ", orange are runs where the RPi4 throttled the CPU";
	    break;
	default:
	    exit(1, "FATAL: Unhandled systemid %O\n", runspecifics->systemid);
	}
	
	string template = Stdio.read_file("chart-template.js");
	string out = replace( template,
	      ({ "¤TABLEDATA¤", "¤CHARTDATA¤", "¤SYSTEMDESC¤", "optgraph = 0"}),
	      ({ table_data,    chart_data,    system_desc,    "optgraph = 1"})
			      );
	string compilerid = runspecifics->compiler;
	if(runspecifics->opt_id)
	    compilerid += "-"+opt_id;
	string benchid = shortname +"-"+ compilerid +"-"+ type;
	string compiler_desc = runspecifics->compiler +" "+ runspecifics->ccoptions;
	    
	mkdir("output");
	Stdio.cp("index.html", "output/index.html");
	Stdio.write_file("output/"+benchid+".js", out);

	template = Stdio.read_file("html-template.html");
	out = replace( template,
		       ({ "¤MAMEFLAGS¤", "¤BENCHID¤", "¤SYSTEMDESC¤", "¤COMPILERDESC¤", "¤RPIDESC¤" }),
		       ({ flags,         benchid,     system_desc,    compiler_desc,    system_extra_desc }) );
	Stdio.write_file("output/"+benchid+".html", out);	
    }
    if(VERBOSE) {
      // stats->games = "removed (too verbose)";
      werror("stats: %O\n", stats);
    }
}