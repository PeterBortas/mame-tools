google.charts.load('current', {'packages':['corechart', 'table']});
google.charts.setOnLoadCallback(drawCharts);

// The line chart does not have it's own resize handling
// TODO: Preserve selections, ether with wrapper (ref: https://stackoverflow.com/questions/50935900/how-to-redraw-a-google-visualization-chart-without-re-passing-the-data) or save options globally
window.onresize = drawCharts;

function drawCharts() {
    //CSS for table
    var cssClassNames = {
	// 'headerRow': 'italic-darkblue-font large-font bold-font',
	// 'tableRow': '',
	// 'oddTableRow': 'beige-background',
	// 'selectedTableRow': 'orange-background large-font',
	// 'hoverTableRow': '',
	// 'headerCell': 'gold-border',
	// 'tableCell': 'orange-background',
	// 'rowNumberCell': 'underline-blue-font'
      };

    ¤TABLEDATA¤

    var tdata = new google.visualization.DataTable(jsonData);
    var tformatter = new google.visualization.NumberFormat({
	fractionDigits: 0
    });
    // Overshoots a bit on the number of columns, but that's fine
    for(i=2; i<tdata.getNumberOfColumns(); i++) {
	tformatter.format(tdata, i);
    }
    var table = new google.visualization.Table(document.getElementById('table_div'));

    var toptions = {'showRowNumber': true, 'width': '100%', 'allowHtml': true, 'cssClassNames': cssClassNames};
    
    table.draw(tdata, toptions);

    ¤CHARTDATA¤

    var cdata = new google.visualization.DataTable(jsonChart);

    var coptions = {
        title: 'Mame™ benchmarks (% of real-time, higher is better) running on ¤SYSTEMDESC¤',
	// curveType: 'function',
        legend: { position: 'bottom' },
	// vAxis: { scaleType: 'log' },
	// vAxis: {title: '% of realtime'},
	// hAxis: {title: 'Mame version'},
	vAxis: {format: 'percent'},
	//hAxis: {format: '#.###'}, // This removes 4th+ digit, but also removes trailing 0s
	// trendlines: { 0: {visibleInLegend: true} }
	// trendlines: {
	//     0: {
	//  	type: 'polynomial',
	//  	degree: 3,
	//  	visibleInLegend: true,
	//     },
	//     1: {}
	// },
	annotations: { // FIXME: Turn off annotation stems too
	    textStyle: {
		opacity: 0.0 // Do not show annotations by default
	    }
	},
	tooltip: { isHtml: true }, //FIXME: tooptips need better colours
    };
    
    var optgraph = 0; // Used to hardcode opt graphs with replace
    if(optgraph) {
	coptions.annotations = {
	    textStyle: { opacity: 1.0 }
	}
	console.log("force-enabling annotation:", toptions);
    }

    var chart = new google.visualization.LineChart(document.getElementById('curve_chart'));
    chart.draw(cdata, coptions);

    function toggleVisible(event) {
	var sel = table.getSelection();
	// console.log("event selection:", sel);
	if (sel.length > 0) {
            if (sel[0].row == null) {
		// if row is null, we clicked on the legend, probably does no good for table
		console.log('clicked on the legend');
            } else {
		table_row = sel[0].row;
		console.log('selected (at least) '+ table_row +", "+ tdata.getValue(table_row, 0));

		// Special case cel selections
		// FIXME: column returns 0, workaround here:
		// https://stackoverflow.com/questions/20165281/google-chart-getselection-doesnt-have-column-property
		// if(sel.length == 1) {
		//     console.log("row: "+ sel[0].row);
		//     console.log("column: "+ sel[0].column);
		//     if( tdata.getValue(sel[0].row, sel[0].column) == null ) {
		// 	colsole.log('selection is nil');
		//     }
		// }
		
		// 0th entry in line-chart data is the version list
		var show_columns = [ 0 ];
		var games = []; // For updating the hash part of the URL
		sel.forEach( function(item) {
		    // The table on the other hand is indexed from 0,
		    // so add 1.  Then compensate for 3 extra
		    // interval/tooltip/annotation columns by *5 and
		    // grabbing all 5 columns for that game
		    show_columns.push(item.row*5+1);
		    show_columns.push(item.row*5+2);
		    show_columns.push(item.row*5+3);
		    show_columns.push(item.row*5+4);
		    show_columns.push(item.row*5+5);
		    games.push( tdata.getValue(item.row, 0) );
		});
		// console.log("event show_colums:", show_columns);
		var gameHash = games.join(":");
		// console.log("event gameHash:", gameHash);
		
		// If only two games are selected, add trendlines
		var trendoptions = Object.assign({}, coptions);
		if(!optgraph && sel.length<3) {
		    trendoptions.trendlines = {
			0: {
	 		    type: 'polynomial',
	 		    degree: 3,
	 		    visibleInLegend: false,
			},
			1: {},
		    }
		}

		// If only a few games are selected, add show the annotations
		if(optgraph || sel.length<8) {
		    trendoptions.annotations = {
			textStyle: { opacity: 1.0 }
		    }
		}

		// FIXME: Show intervals when few enough games are selected, as with trends
		
		var filtered_view = new google.visualization.DataView(cdata);
		filtered_view.setColumns(show_columns);
		chart.draw(filtered_view, trendoptions);
		location.hash = gameHash;
	    }
        } else {
	    console.log('de-selected, showing all data');
	    chart.draw(cdata, coptions);
	    location.hash = ""
	}
    }    
    
    // FIXME: Does not trigger for table. Works for chart, jQuery workaround here:
    // https://stackoverflow.com/questions/18735594/handling-a-hover-event-for-a-google-charts-table
    // https://stackoverflow.com/questions/51537783/tooltip-html-for-table-google-visualisation
    // function setTooltipContent(event) {
    // 	alert('You hovered');

    // 	var dataTable = table;
    // 	var row = event.row;
    // 	var col = event.col;
	
    // 	if (row != null) {
    //         var content = '<div class="custom-tooltip" ><h1>' +
    // 		dataTable.getValue(row, 0) + '</h1><div>' +
    // 		dataTable.getValue(row, 1) + '</div></div>'; //generate tooltip content
    //         var tooltip = document.getElementsByClassName("google-visualization-tooltip")[0];
    //         tooltip.innerHTML = content;
    // 	}
    // }

    google.visualization.events.addListener(table, 'select', toggleVisible);
    // google.visualization.events.addListener(chart, 'onmouseover', setTooltipContent);

    // Make it possible to make URLs with preselected games
    var hashValue = location.hash
    if(hashValue) {
	var hash = hashValue.split("#")[1]; // Remove initial #
	var games = hash.split(":");
	console.log("Games from hash: ", games);

	// extract non-game parameters
	var drivers = [];
	var realgames = [];
	games.forEach( function(game, index) {
	    var i = game.search(";");
	    if(i != -1) {
		parameter = game.substring(0, i);
		switch(parameter) {
		case "driver":
		    drivers.push(game.substring(i+1));
		    break;
		default:
		    console.log("unknown parameter: ", game);
		}
	    } else {
		realgames.push(game);
	    }		
	});
	games = realgames;

	if(drivers.length == 0) {
	    console.log("drivers: Nope!");
	} else {
	    console.log("drivers: ", drivers);
	}
	
	var select_rows = [];
	if(games.length != 0) { //There are games
	    games.forEach( function(game, index) {
		var query = {"column":0, "value":game};
		var selection = tdata.getFilteredRows([ query ]);
		console.log("selection for "+ game +":", selection);
		if(drivers.length == 0) {
		    console.log("No drivers, so show all");
		    select_rows.push({row:selection[0],column:null});
		} else {
		    // FIXME: This is not very useful, OR games and drivers instead
		    var driver = tdata.getValue(item.row, 1)
		    console.log("Filtering on drivers", drivers, driver);
		    if(drivers.indexOf(driver) != -1) {
			console.log("Driver found", driver);
			select_rows.push({row:selection[0],column:null});
		    }
		}
	    });
	} else {
	    if(drivers.length != 0) { //No games, but drivers, OR them
		drivers.forEach( function(driver, index) {
		    var query = {"column":1, "value":driver};
		    var selection = tdata.getFilteredRows([ query ]);
		    console.log("selection for "+ driver +":", selection);
		    selection.forEach( function(rownr) {
			select_rows.push({row:rownr,column:null});
		    });
		});
	    }
	}
	console.log("select_rows: ", select_rows);
	
	table.setSelection(null); // Clear existing selections
	table.setSelection( select_rows );
	
	// Fire a select event.
	google.visualization.events.trigger(table, 'select', null);
    }
}
