my @files;
my @allhash;
my @codehash;
my @datehash;
my @values;

mkdir ("./codes");

opendir(DIR, ".") || die "Can't open directory $somedir: $!";
# @files = grep { (!/^\./) && -f "$somedir/$_" } readdir(DIR);
@files = grep { (/TXT|csv/i) && -f "./$_" } readdir(DIR);
closedir DIR;

$allhash = {};

foreach my $file (@files) {
	open DATEFILE, "<", $file;
	my @codes = readline (DATEFILE);
	close DATEFILE;
	chomp(@codes);
	foreach $codeline (@codes) {
		@values = split(/,/, $codeline);
		$code = $values[0];
		$date = $values[1];
		if ( $date =~ /(.*)\/(.*)\/(.*)/ ) {
			$date = $3.$2.$1;
		}
		
		$datehash = {};
		$datehash->{"Code"} = $code;
		$datehash->{"Date"} = $date;
		$datehash->{"Open"} = $values[2];
		$datehash->{"High"} = $values[3];
		$datehash->{"Low"} = $values[4];
		$datehash->{"Close"} = $values[5];
		$datehash->{"Volume"} = $values[6];
		
		$codehash = $allhash->{$code};
		if (undef eq $codehash) {
			$codehash = {};
			$allhash->{$code} = $codehash;
		}
		$codehash->{$date} =  $datehash;
	}
}

foreach $code ( sort keys $allhash ) {
	print $code."\n";
	$codehash = $allhash->{$code};
	
	open CODE, ">>", "codes/$code.txt";
	foreach $codedate( sort keys $codehash ) {
		$datehash = $codehash->{$codedate};

		print CODE $datehash->{"Code"}.",";
		print CODE $datehash->{"Date"}.",";
		print CODE $datehash->{"Open"}.",";
		print CODE $datehash->{"High"}.",";
		print CODE $datehash->{"Low"}.",";
		print CODE $datehash->{"Close"}.",";
		print CODE $datehash->{"Volume"}."\n";
	}
	close CODE;
}
