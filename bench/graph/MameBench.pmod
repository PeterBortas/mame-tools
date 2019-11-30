mapping runspecifics = ([]); // Common for the entire benchmark, such
			     // as system type, optimization details
			     // and similar

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

void create()
{
    string foo = "bar";
}
