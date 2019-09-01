#!/usr/bin/env pike

// TODO: Clean up the parser mess

mapping parse_filename(string filename)
{
    mapping res = ([]);
    //example: kof98-0.175-1750-gcc8.result
    if(sscanf(filename, "%s-0.%d-%d-%s.result",
	      res->game, res->version, res->freq, res->compiler) == 4) {
	if(res->freq != 1750)
	    exit(1, "FATAL: Fix the parser to handle overclocking!\n");
	if(res->compiler != "gcc8")
	    exit(1, "FATAL: Fix the parser to handle compilers!\n");
	return res;
    } else {
	exit(1, "FATAL: Unable to parse filename '%s'\n", filename);
    }
}

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
		exit(1, "WARNING: Failed to parse line %d '%s' in \n%s\n",
		     lnr, line, filename);
	    }
	    break;
	case 1:
	    int matches = sscanf(line, "%s%*[ ]\"%s\"", res->game, res->game_desc);
	    if(matches != 3) {
		exit(1, "WARNING: Failed to parse line %d '%s' in \n%s\n",
		     lnr, line, filename);
	    }
	    break;
	default:
	    if(sscanf(line, "Before run: %d throttled=%s",
		      int dummy1, string dummy2) == 2) {
		res->temp_before = dummy1;
		res->throttled_before = dummy2;
	    }
	    if(sscanf(line, "After run: %d throttled=%s",
		      int dummy1, string dummy2) == 2) {
		res->temp_after = dummy1;
		res->throttled_after = dummy2;
	    }
	    if(line == "Running real emulation benchmark") {
		current_test_type = "real";
		res->real = ([]);
	    }
	    if(line == "Running built in benchmark") {
		current_test_type = "bench";
		res->bench = ([]);
	    }
	    if(sscanf(line, "Average speed: %d.%d%% (%d seconds)",
		      int dummy1, int dummy2, int dummy3) == 3) {
		// % is float, but to avoid float conversion
		// in this step grab ints and concatenate them
		res[current_test_type]->percent = dummy1 +"."+ dummy2;
		res[current_test_type]->runtime = dummy3;
		
		if(res[current_test_type]->runtime != 89)
		    exit(1, "FATAL: test runtime in '%s' is not 89s!", filename);
	    }
	    break;
	}
    }    
    return res;
}

string create_table(mapping all_results)
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
			       //version, so same a complete list
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
    // werror("%O\n", gamedata);

    foreach(sort(indices(gamedata)), string game) {
	array vbenches = ({});
	string game_desc;
	// foreach(sort(indices(gamedata[game])), string version) {
	foreach(all_versions, string version) {
	    //werror("gdg->v: %O\n", gamedata[game][version]);
	    //werror("v: %O\n", version);
	    if(gamedata[game][version]) {
		game_desc = gamedata[game][version]->game_desc; // Keep the newest one
		if( !gamedata[game][version]->bench ||
		    !gamedata[game][version]->bench->percent )
		{
		    // There is and entry, but it lacks data due to crash or timeout
		    //TODO: Using Var.Null breaks encoding
		    vbenches += ({ (["v":"null", "p":([
					 "style": "color:#006600; background-color:grey;",
				     ]) ]) });
		} else {
		    // Regular good entry
		    float percent = (float)gamedata[game][version]->bench->percent;
		    if(gamedata[game][version]->throttled_before != "0x0" ||
		       gamedata[game][version]->throttled_after != "0x0") {
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

	//FIXME: Driver should be extracted at runtime, but that is
	//       not currently done
	tdata->rows += ({
	    (["c": ({
		(["v":game]),
		(["v":"driver NA"]),
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

// TODO: clean up both create_* functions, they contain a lot of cut'n'paste
string create_chart(mapping all_results)
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
    
    cdata->cols += ({ (["id":"", "label":"Version", "pattern":"", "type":"string"]) });
    array all_versions = ({}); //Games might not have results for all
			       //version, so same a complete list
    all_versions = sort(indices(all_results));

    foreach(sort(indices(gamedata)), string game) {
	cdata->cols += ({ (["id":"","label":game, "pattern":"","type":"number"]) });
    }

    foreach(all_versions, string version) {
	array vbenches = ({});
	string game_desc;
	// foreach(sort(indices(gamedata[game])), string version) {
	foreach(sort(indices(gamedata)), string game) {
	    if(gamedata[game][version]) {
		game_desc = gamedata[game][version]->game_desc; // Keep the newest one
		if( !gamedata[game][version]->bench ||
		    !gamedata[game][version]->bench->percent )
		{
		    // There is an entry, but it lacks data due to crash or timeout
		    //TODO: Using Var.Null breaks encoding
		    vbenches += ({ (["v":"null", "p":([
					 "style": "color:#006600; background-color:grey;",
				     ]) ]) });
		} else {
		    // Regular good entry
		    float percent = (float)gamedata[game][version]->bench->percent;
		    if(gamedata[game][version]->throttled_before != "0x0" ||
		       gamedata[game][version]->throttled_after != "0x0") {
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

int main(int argc, array argv)
{
    if(argc != 2) {
	exit(1, "Usage: create_graph.pike <gamelist file>\n"
	        "Example: create_graph.pike games.lst\n");
    }
    string listfile = argv[1];
    string result_base = "/mametest/mame-tools/bench/runstate/gameresults/";

    array result_files = get_dir(result_base);
    mapping all_results = ([]);
    object games = Stdio.File(listfile)->line_iterator();
    foreach(games; int lnr; string game) {
	if(game[0..0] == "#")
	    continue; // Skip comments

	// The result files are not in a good format
	foreach( glob(game+"*", result_files), string resultfile ) {
	    string filename = result_base + resultfile;
	    mapping fileinfo = parse_filename(filename);
	    // werror("file: %s\n", filename);

	    mapping res = parse_result(filename);
	    // werror("DEBUG fileinfo: %O\n", fileinfo);

	    string mameversion = "0."+ fileinfo->version;
	    if(! all_results[mameversion])
		all_results[mameversion] = ([]);
	    all_results[mameversion][game] = res;
	}
    }
    //    werror("%O\n", all_results);

    string table_data = create_table(all_results);
    string chart_data = create_chart(all_results);
    // werror("DEBUG table_data:\n%s\n", table_data);
    // werror("DEBUG chart_data:\n%s\n", chart_data);

    string template = Stdio.read_file("chart-template.js");
    string out = replace( template,
			  ({ "¤TABLEDATA¤", "¤CHARTDATA¤" }),
			  ({ table_data,    chart_data    }) );
    write(out);
}
