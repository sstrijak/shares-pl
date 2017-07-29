my @files;

$stopdate = $ARGV[0];

$macd1 = 12;
$macd2 = 26;
$macds = 9;

#Multiplier: (2 / (Time periods + 1) )
$ms = (2 / ($macds + 1) );
$m1 = (2 / ($macd1 + 1) );
$m2 = (2 / ($macd2 + 1) );

opendir(DIR, ".") || die "Can't open directory $somedir: $!";
# @files = grep { (!/^\./) && -f "$somedir/$_" } readdir(DIR);
@files = grep { (/txt|csv/i) && -f "./$_" } readdir(DIR);
closedir DIR;

open SIGNALS, ">", "_signals.sig";
open DATA, ">", "_data.sig";

foreach my $file (@files) {
	open CODEFILE, "<", $file;
	my @pricelines = readline (CODEFILE);
	close CODEFILE;
	chomp(@pricelines);
	# Extract close prices
	@closeprices = ();
	@dates = ();
	
	foreach $priceline (@pricelines) {
		@values = split(/,/, $priceline);
		push (@closeprices, $values[5]);
		push (@dates, $values[1]);
	}
	
	@price1 = ();
	@price2 = ();
	@macd = ();
	@macdsignal = ();
	@macdhisto = ();

	for ($i = 0; $i <= $#closeprices; $i++) {
		# $macd1 price EMA
		if ( $i < $macd1 - 1 ) { 
			push (@price1, 0); 
		} elsif ( $macd1 - 1 == $i ) { 
			push (@price1, sma ( \@closeprices, $macd1, $macd1) ); 
		} else {
			# EMA: {Close - EMA(previous day)} x multiplier + EMA(previous day). 
			$ema = ( $closeprices[$i] - $price1[$i-1] ) * $m1 + $price1[$i-1];
			push (@price1, $ema); 
		}

		# $macd2 price EMA
		if ( $i < $macd2 - 1 ) { 
			push (@price2, 0); 
		} elsif ( $macd2 - 1 == $i ) { 
			push (@price2, sma ( \@closeprices, $macd2, $macd2) ); 
		} else {
			# EMA: {Close - EMA(previous day)} x multiplier + EMA(previous day). 
			$ema = ( $closeprices[$i] - $price2[$i-1] ) * $m2 + $price2[$i-1];
			push (@price2, $ema); 
		}

		# MACD
		if ( $i < $macd2 ) { 
			push (@macd, 0); 
		} else { 
			push (@macd, $price1[$i] - $price2[$i] ); 
		}
		
		# $macds MACD EMA - MACD signal
		if ( $i < $macds - 1  ) { 
			push (@macdsignal, 0); 
		} elsif ( $macds - 1 == $i ) { 
			push (@macdsignal, sma ( \@macd, $macd2, $macds) ); 
		} else {
			# EMA: {Close - EMA(previous day)} x multiplier + EMA(previous day). 
			$ema = ( $macd[$i] - $macdsignal[$i-1] ) * $ms + $macdsignal[$i-1];
			push (@macdsignal, $ema); 
		}
		# MACD Histogram
		$histo = $macd[$i] - $macdsignal[$i];
		push (@macdhisto, $histo);
		print DATA $file.",data,".$dates[$i].",".$macd[$i].",".$macdsignal[$i]."\n";
		
		$lasthisto = $macdhisto[$i-1];
		if ( $lasthisto > 0 and $histo < 0) {
			print SIGNALS $file.",sell,".$dates[$i]."\n";
		}
		if ( $lasthisto < 0 and $histo > 0) {
			print SIGNALS $file.",buy,".$dates[$i]."\n";
		}
	}
}
close SIGNALS;
close DATA;

sub sma {
	my $closeprices = @_[0];
	my $checkpoint = @_[1];
	my $period  = @_[2];
	my $sma = 0;
	my $i = 0;
	
	if ( $checkpoint < $period ) { return -1 };
	if ( $checkpoint > $#$closeprices ) { return -1 };
	
	# Count price cxheckpoints starting from 1, array starts from 0
	for ($i = $checkpoint - $period; $i < $checkpoint; $i++ ) {
		$sma = $sma + $closeprices[$i];
	}
	$sma = $sma / $period;
	return $sma;
}
