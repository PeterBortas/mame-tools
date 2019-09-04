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

    // TODO: Install hook to redraw line-graph if the window is resized?
    
    ¤TABLEDATA¤

    var tdata = new google.visualization.DataTable(jsonData);
    var table = new google.visualization.Table(document.getElementById('table_div'));

    var toptions = {'showRowNumber': true, 'width': '100%', 'allowHtml': true, 'cssClassNames': cssClassNames};
    
    table.draw(tdata, toptions);

    ¤CHARTDATA¤

    var cdata = new google.visualization.DataTable(jsonChart);

    var coptions = {
        title: 'Mame™ benchmarks (% of real-time, higher is better) for RPi4, 2G RAM, overclocked to 1.75GHz',
	// curveType: 'function',
        legend: { position: 'bottom' },
	// vAxis: { scaleType: 'log' }
	// hAxis: {title: 'Mame version'},
	// vAxis: {title: '% of realtime'},
	// trendlines: { 0: {visibleInLegend: true} }
	// trendlines: {
	//     0: {
	//  	type: 'polynomial',
	//  	degree: 3,
	//  	visibleInLegend: true,
	//     },
	//     1: {}
	// }
    };
    
    var chart = new google.visualization.LineChart(document.getElementById('curve_chart'));
    chart.draw(cdata, coptions);

    function toggleVisible() {
	var sel = table.getSelection();
	if (sel.length > 0) {
            if (sel[0].row == null) {
		// if row is null, we clicked on the legend, probably does no good for table
		console.log('clicked on the legend');
            } else {
		table_row = sel[0].row;
		console.log('selected (at least) '+ table_row +", "+ tdata.getValue(table_row, 0));
		console.log(sel);
		// 0th entry in line-chart data is the version list
		var show_columns = [ 0 ];
		sel.forEach( function(item) {
		    // The table on the other hand is indexed from 0, so add 1
		    show_columns.push(item.row+1);
		});

		// If only two games are selected, add trendlines
		var trendoptions = Object.assign({}, coptions);
		if(sel.length<3) {
		    trendoptions.trendlines = {
			0: {
	 		    type: 'polynomial',
	 		    degree: 3,
	 		    visibleInLegend: false,
			},
			1: {},
		    }
		}

		var filtered_view = new google.visualization.DataView(cdata);
		filtered_view.setColumns(show_columns);
		chart.draw(filtered_view, trendoptions);
	    }
        } else {
	    console.log('de-selected, showing all data');
	    chart.draw(cdata, coptions);
	}
    }    
    
    google.visualization.events.addListener(table, 'select', toggleVisible);
}
