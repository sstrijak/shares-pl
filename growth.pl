#!/usr/bin/perl

sub growth () {
	my $now = $_[0];
	my $before = $_[1];
	
	$growth = 0;
	
	if ( $now == -999 or $before == -999 ) { $growth = -999; }
	else
	{
		# Where I2 = previous period & G2 = current period
		#=IF(AND(I2<=0,G2>=0),(G2-I2)/ABS(I2),
		#		IF(AND(I2<=0,I2<=G2),(ABS(G2)-ABS(I2))/(I2),
		#			IF(AND(I2>=0,G2<=0),(G2-I2)/I2,
		#				IF(AND(I2>=0,G2>=0),(G2-I2)/I2,
		#					IF(AND(I2<=0,I2>=G2),(ABS(G2)-ABS(I2))/(I2)

		if ( $before == 0 )
		{
			if ( $now == 0 ) { $growth = 0; }
			if ( $now > 0 ) { $growth = 25; }
			if ( $now < 0 ) { $growth = -25; }
		}
		elsif ( $before <= 0 and $now >=0 ) 		{ $growth = ($now - $before) / abs($before) ; }
		elsif ( $before <= 0 and $before <= $now ) 	{ $growth = (abs($now) - abs($before)) / $before ; }
		elsif ( $before >= 0 and $now <=0 )	 	{ $growth = ($now - $before) / $before ; }
		elsif ( $before >= 0 and $now >=0 )	 	{ $growth = ($now - $before) / $before ; }
		elsif ( $before <= 0 and $before >= $now  )	{ $growth = (abs($now) - abs($before)) / $before ; }
		$growth = $growth * 100;
	}
	return $growth;
}

1;