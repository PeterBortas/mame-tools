#!/usr/bin/env pike

#include "benchmark.h"
constant mode = "opthack"; // control some script specific modes

object Bench;
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

    if(mode == "opthack")
	werror("Processing %O\n", listfile);

    Bench = .MameBench;
    Bench->create(mode);

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
	    mapping result = Bench.parse_result(filename, opt_id);

	    // The opt_id didn't match, result is damaged, or we
	    // purposly avoid version
	    if(!result) 
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
		foreach( indices(Bench.test_types), string type) {
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
    foreach( indices(Bench.test_types), string type) {
	// create_chart has the side effect of setting up some
	// statistics needed for create_table, so the ordering is
	// important
	string chart_data = Bench.create_chart(all_results, type);
	string table_data = Bench.create_table(all_results, type);
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

	if(VERBOSE)
	    werror("runspecifics: %O\n", Bench.runspecifics);

	string cpus = "";
	if(Bench.runspecifics->sockets > 1)
	    cpus = sprintf("%d x ", Bench.runspecifics->sockets);

	string system_desc, system_extra_desc="";
	switch(Bench.runspecifics->systemid) {
	case "xeon_x5570": //crux
	    system_desc = cpus +"Xeon X5570, "+ Bench.runspecifics->systemram +"G RAM, @2.93GHz. WARNING: machine not idle, only for testing, not usable as benchmark!";
	    break;
	case "xeon_e5_2660": //analysator
	    //Nodes have a minimum of 32G, hardcode it
	    system_desc = cpus +"Xeon E5-2660, 32G+ RAM, @2.20GHz";
	    break;
	case "rpi4_1.75":
	    system_desc = "RPi4, "+ Bench.runspecifics->systemram +"G RAM, overclocked to 1.75GHz";
	    system_extra_desc = ", orange are runs where the RPi4 throttled the CPU";
	    break;
	default:
	    exit(1, "FATAL: Unhandled systemid %O\n", Bench.runspecifics->systemid);
	}
	
	string template = Stdio.read_file("chart-template.js");
	string out = replace( template,
	      ({ "¤TABLEDATA¤", "¤CHARTDATA¤", "¤SYSTEMDESC¤", "optgraph = 0"}),
	      ({ table_data,    chart_data,    system_desc,    "optgraph = 1"})
			      );
	string compilerid = Bench.runspecifics->compiler;
	if(Bench.runspecifics->opt_id)
	    compilerid += "-"+opt_id;
	string benchid = shortname +"-"+ compilerid +"-"+ type;
	string compiler_desc = Bench.runspecifics->compiler +" "+ Bench.runspecifics->ccoptions;
	    
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
	if(mode != "opthack")
	    Bench.stats->games = "removed (too verbose)";
	werror("stats: %O\n", Bench.stats);
    }
}
