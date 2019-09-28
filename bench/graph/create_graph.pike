#!/usr/bin/env pike

// TODO: Clean up the parser mess

string global_compiler; // Verify that all results are from the same compiler
void verify_compiler(string compiler)
{
    if(!global_compiler)
	global_compiler = compiler;
    else {
	if(global_compiler != compiler)
	    exit(1, "FATAL: compiler missmatch, %O != %O", compiler, global_compiler);
    }
}

//FIXME: Get all details from the files
// Still in use:
//    res->mameversion
mapping parse_filename(string filename)
{
    mapping res = ([]);
    filename = basename(filename);

    //example: 1943-xeon_x5570-0.212-gcc5.result.1
    if(sscanf(filename, "%s-%s-0.%d-%s.result.%d",
	      res->game, res->shortname, res->mameversion, res->compiler, res->runnr) == 5) {
	return res;
    }

    exit(1, "FATAL: Unable to parse filename '%s'\n", filename);
}

mapping test_types = ([]); // Keep track of which types have been seen
mapping parse_result(string filename)
{
    object resultlines = Stdio.File(filename)->line_iterator();
    mapping res = ([]);
    string current_test_type;	    
    foreach(resultlines; int lnr; string line) {
	// werror("line: '%s'\n", line);
	switch(lnr) {
	case 0:
	    if(sscanf(line, "Name:%*[ ]Description:") != 1) {
		werror("WARNING: Failed to parse line %d '%s' in \n%s\n",
		       lnr, line, filename);
		return res;
	    }
	    break;
	case 1:
	    int matches = sscanf(line, "%s%*[ ]\"%s\"", res->game, res->game_desc);
	    if(matches != 3) {
		werror("WARNING: Failed to parse line %d '%s' in \n%s\n",
		       lnr, line, filename);
		return res;
	    }
	    break;
	default:
	    int temp;
	    string throttled;
	    if(sscanf(line, "Before run: %d throttled=%s",
		      int temp, string throttled) == 2) {
		res->temp_before = temp;
		res->throttled_before = throttled;
	    }
	    if(sscanf(line, "After run: %d throttled=%s",
		      int temp, string throttled) == 2) {
		res->temp_after = temp;
		res->throttled_after = throttled;
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
		
		if(res[current_test_type]->runtime != 89)
		    exit(1, "FATAL: test runtime in '%s' is not 89s!", filename);
	    }
	    if(line == "Fatal error: Required files are missing, the machine cannot be run.")
	    {
		res[current_test_type]->failtype = "missing files";
	    }
	    if(sscanf(line, "CC: %s", string compiler) == 1) {
		verify_compiler(compiler);
		res->compiler = compiler;
	    }
	    if(sscanf(line, "Mame: %s", string version) == 1) {
		res->mameversion = version;
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
		    // FIXME: Should not need cast any more
		    float percent = (float)gamedata[game][version][type]->percent;
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
	// Notes about game are hardcoded here
	// FIXME: Move this to a separate file
	switch(game) {
	case "cubeqst":
	    note = (["v":"†"]); break;
	default:
	    note = (["v":""]); break;
	}

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


mapping stats = ([]);
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
    }

    foreach(all_versions, string version) {
	array vbenches = ({});
	string game_desc;
	// foreach(sort(indices(gamedata[game])), string version) {
	foreach(sort(indices(gamedata)), string game) {
	    if(gamedata[game][version]) {
		game_desc = gamedata[game][version]->game_desc; // Keep the newest one
		if( !gamedata[game][version][type] ||
		    !gamedata[game][version][type]->percent )
		{
		    stats->crashed += 1;
		    // There is an entry, but it lacks data due to crash or timeout
		    //TODO: Using Var.Null breaks encoding
		    vbenches += ({ (["v":"null", "p":([
					 "style": "color:#006600; background-color:grey;",
				     ]) ]) });
		} else {
		    // Regular good entry

		    float percent = (float)gamedata[game][version][type]->percent;
		    if(gamedata[game][version]->throttled_before != "0x0" ||
		       gamedata[game][version]->throttled_after != "0x0") {
			stats->throttled += 1;
			vbenches += ({ (["v":percent, "p":(["style": "background-color:orange;" ]) ]) });
		    } else {
			stats->good += 1;
			vbenches += ({ (["v":percent]) });
		    }
		    
		}
	    } else {
		// There is no entry of this game for this version
		stats->missing += 1;
		vbenches += ({ (["v":"null" ]) });
	    }
	    if(gamedata[game][version][type] &&
	       gamedata[game][version][type]->multi_percent) {
		// Handles multiple runs. Straight average for now
		// NOTE: copy_value if the order ever becomes important
		array speeds = gamedata[game][version][type]->multi_percent;
		float min_percent = sort(speeds)[0];
		float max_percent = sort(speeds)[-1];
		werror("min: %f, max: %f\n", min_percent, max_percent);
		// FIXME: This will require experimenting with explicit column roles. See https://developers.google.com/chart/interactive/docs/roles
		vbenches += ({ (["v":min_percent]) });
		vbenches += ({ (["v":max_percent]) });
	    } else {
		vbenches += ({ (["v":"null"]) });
		vbenches += ({ (["v":"null"]) });
	    }
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
    if(drivercache[game])
	return drivercache[game];
    
    string exe = "/mametest/arch/x86_64-64/stored-mames/mame0214-gcc8-24d07a1/mame64";
    mapping res = Process.run( ({ exe, "-listsource", game }) );
    if(res->exitcode)
	exit(1, "FATAL: Failed to get driver for %s\n", game);
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
	exit(1, "Usage: create_graph.pike <gamelist file> <system shortname>\n"
	     "Examples:\n"
	     "    ./create_graph.pike ../games.lst rpi4_1.75\n"
	     "    ./create_graph.pike ../games.lst xeon_x5570\n");
    }
    string listfile = argv[1];
    string shortname = argv[2];
    string result_base = "/mametest/mame-tools/bench/benchresult/"+ shortname +"/";

    array result_files = get_dir(result_base);
    mapping all_results = ([]);
    object games = Stdio.File(listfile)->line_iterator();
    foreach(games; int lnr; string game) {
	if(game[0..0] == "#")
	    continue; // Skip comments

	// The result files are a bit free form because they are
	// partly the output from the mame binary
	foreach( glob(game+"-*", result_files), string resultfile ) {
	    string filename = result_base + resultfile;
	    mapping result = parse_result(filename);

	    // werror("result: %O\n", result);
	    
	    string mameversion = result->mameversion;
	    if(! all_results[mameversion])
		all_results[mameversion] = ([]);

	    if(all_results[mameversion][game]) {
		//FIXME: This ignores every parameter except the speed value
		foreach( indices(test_types), string type) {
		    if(result[type] && result[type]->percent) {
			if(!all_results[mameversion][game][type]->multi_percent)
			    all_results[mameversion][game][type]->multi_percent = ({});
			all_results[mameversion][game][type]->multi_percent += ({ result[type]->percent });
			all_results[mameversion][game][type]->percent = `+(@all_results[mameversion][game][type]->multi_percent) / sizeof(all_results[mameversion][game][type]->multi_percent);
		    }
		}
	    } else {
		all_results[mameversion][game] = result;
	    }
	    // werror("all_result[ver][game]: %O\n", all_results[mameversion][game]);
	}
    }

    // FIXME: write down more data in the results files so the hardcoding can stop
    foreach( indices(test_types), string type) {
	string table_data = create_table(all_results, type);
	string chart_data = create_chart(all_results, type);
	// werror("DEBUG table_data:\n%s\n", table_data);
	// werror("DEBUG chart_data:\n%s\n", chart_data);

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
	
	string template = Stdio.read_file("chart-template.js");
	string out = replace( template,
			      ({ "¤TABLEDATA¤", "¤CHARTDATA¤" }),
			      ({ table_data,    chart_data    }) );
	string benchid;
	benchid = shortname +"-"+ global_compiler +"-"+ type;
	    
	mkdir("output");
	Stdio.cp("index.html", "output/index.html");
	Stdio.write_file("output/"+benchid+".js", out);

	template = Stdio.read_file("html-template.html");
	out = replace( template,
		       ({ "¤MAMEFLAGS¤", "¤BENCHID¤" }),
		       ({ flags,         benchid     }) );
	Stdio.write_file("output/"+benchid+".html", out);	
    }
    werror("stats: %O\n", stats);
}
