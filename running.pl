#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw( Date_to_Days );
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
use GD::Graph::lines;
use GD::Graph::Data;

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});

# File and directories
$logfile = "$mypath/$pname.log";

# SMTP
my $smtpserver = 'mail.7r.com.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";
my $subject = "$pname on $starttime";
my $otomessage = "";
my $message = "";

# mySQL
my $dbname = "shares";
my $dbhost = "localhost";
my $dbport = 3306;
my $dbuser = "shares";
my $dbpassword = "D3l3t312";
my $dbtable = "stocks";

# Flow control and reporting
my $keepgoing = 1;

# Script data
my $date = "";
my $code = "";
my $issues = 0;
my $price = 0;
my $investment = 0;
my %alldates = {};
my @allcodes = ();


open LOG, ">>", $logfile;


my $dsn = "DBI:mysql:database=$dbname;host=$dbhost;port=$dbport";
my $dbh = DBI->connect($dsn, $dbuser, $dbpassword);
my $error = $dbh->{'mysql_error'};

if ( $error)
{
	$thismessage = "Error connecting to database: $error";
	logentry ( $thismessage );
	$message .= "$thismessage\n";
	$keepgoing = 0;
}

if ($keepgoing)
{
	# get index data
	$sql = "select date, close from daily where code='XAO'";
	$sthx = $dbh->prepare($sql);
	$result = $sthx->execute();
	while ( @rowx = $sthx->fetchrow_array() ) {
		$date = $rowx[0];
		$close = $rowx [1];
		push @xaoclose, $close;
		$xaodate {$date} = scalar @xaoclose - 1;
	}
	$sthx->finish();

	my %alldates = {};

	# get current portfolio
	$sql = "select code, issues, investment from portfolio";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while (@row = $sth->fetchrow_array())
	{
		$code = $row[0];
		$issues = $row[1];
		$investment = $row[2];
		push @allcodes, $code;
		
		@codeclose = ();
		%codedate = {};
		%running = {};
		
		$sql = "select max(date) from orders where code='$code'";
		$stho = $dbh->prepare($sql);
		$result = $stho->execute();
		if(@rowo = $stho->fetchrow_array()) {

			$startdate = $rowo[0];
			
			$sql = "select date, close from daily where code='$code' and date >= '$startdate'";
			$sthd = $dbh->prepare($sql);
			$result = $sthd->execute();
			while ( @rowd = $sthd->fetchrow_array() ) {
				$date = $rowd[0];
				$close = $rowd [1];
				push @codeclose, $close;
				$codedate {$date} = scalar @codeclose - 1;
			}
			$sthd->finish();

			$sql = "select date from running where code='$code' and date > '$startdate'";
			$sthr = $dbh->prepare($sql);
			$result = $sthr->execute();
			while ( @rowr = $sthr->fetchrow_array() ) {
				$date = $rowr['date'];
				$running{$date} = $date;
			}
			$sthr->finish();
			
			my $datecount = 0;
			
			$startxao = $xaoclose [ $xaodate { $startdate } ];

			foreach $date ( sort keys %codedate ) {
				if ( $date and $datecount++ and ! exists ( $running { $date } ) and $codedate { $date })
				{
					$alldates {$date} = 1;
					$closeindex = $codedate { $date };
					$close = $codeclose[$closeindex];
					$lastclose = $codeclose[$closeindex - 1];
					$value = $issues * $close;
					$delta = $value - $investment;
					$pcnt = $delta / $investment * 100;
					$daydelta = $issues * ( $close - $lastclose ) ;
					$daypcnt = ( $close - $lastclose ) / $lastclose * 100;
					
					$xao = $xaoclose [ $xaodate { $date } ];
					$lastxao = $xaoclose [ $xaodate { $date } -1 ];
					$marketpcnt = ( $xao - $startxao ) / $startxao * 100;
					$marketdaypcnt = ( $xao - $lastxao) / $lastxao * 100;
					
					$sql = "REPLACE INTO `running` SET date='$date', code='$code', issues=$issues, price=$close, investment=$investment,
					        value=$value, delta=$delta, pcnt=$pcnt, marketpcnt=$marketpcnt, 
					        daydelta=$daydelta, daypcnt=$daypcnt, marketdaypcnt=$marketdaypcnt";
					$dbh->do( $sql );
					$error = $dbh->{'mysql_error'};
					if ( $error )
					{
						$thismessage = "Error recording the order: $error";
						logentry ( $thismessage );
						$message .= "$thismessage\n";
						$keepgoing = 0;
					}
				}
			}
 
		}
		$stho->finish();
	}
	$sth->finish();
	
	#calculate totals
	foreach $date ( sort keys %alldates )
	{
		$investment = 0;
		$value = 0;
		$delta = 0;
		$pcnt = 0;
		$daydelta = 0;
		$daypcnt = 0;
		$marketdaypcnt = 0;
		
		$sql = "select investment, value, delta, daydelta, marketpcnt, marketdaypcnt from running where date = '$date'";
		
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while ( @row = $sth->fetchrow_array() )
		{
			$investment += $row[0];
			$value += $row[1];
			$delta += $row[2];
			$daydelta += $row[3];
			if ( $row[4] ) { $marketpcnt = $row[4]; }
			if ( $row[5] ) { $marketdaypcnt = $row[5]; }
		}
		$sth->finish();

		if ( $investment )
		{
			$pcnt = $delta / $investment * 100;
			$daypcnt = $daydelta / $investment * 100;

			$sql = "REPLACE INTO `running` SET date='$date', code='000', investment=$investment,
				value=$value, delta=$delta, pcnt=$pcnt,
				daydelta=$daydelta, daypcnt=$daypcnt, 
				marketpcnt=$marketpcnt, marketdaypcnt=$marketdaypcnt";
			$dbh->do( $sql );
			$error = $dbh->{'mysql_error'};
			if ( $error )
			{
				$thismessage = "Error recording the order: $error";
				logentry ( $thismessage );
				$message .= "$thismessage\n";
				$keepgoing = 0;
			}
		}
	}
	
	push @allcodes, "000";
	$codecount = 0;
	foreach $code ( @allcodes )
	{
		@dates = ();
		@pcnt = ();
		@marketpcnt = ();
		
		$sql = "select date, pcnt, marketpcnt from running where code = '$code' order by date";
		$sth = $dbh->prepare($sql);
		$result = $sth->execute();
		while ( @row = $sth->fetchrow_array() )
		{
			$date = $row[0];
			$codepcnt = $row[1];
			if ( ! $codecount ) { $marketpcnt = $row[2]; }
			
			push @dates, $date;
			push @pcnt, $codepcnt;
			push @marketpcnt, $marketpcnt ;
		}
		$sth->finish();
		
		my @data = (\@dates, \@pcnt, \@marketpcnt);
		my $graph = new GD::Graph::lines(800, 400);

		$graph->set( 
			x_labels_vertical => 1,
			x_label           => 'Trade Date',
			y_label           => '%',
			title             => "$code performance compared to market",
			transparent       => 0,
			fgclr             => [qw(black)],
			dclrs             => [qw(lgray blue)],
			y_number_format   => '%0.2f',
#			x_label_skip      => 5,
			long_ticks        => 1,
		) or warn $graph->error;
		$graph->set_legend("$code", 'XAO');
		
		$graph->plot(\@data) or die $graph->error;

		my $file = "performance-$code.png";
		open(my $out, '>', $file) or die "Cannot open '$file' for write: $!";
		binmode $out;
		print $out $graph->gd->png;
		close $out;
	}
}

# closing
# sendreport ( "Completed" );
close LOG;

sub sendreport () {
	my $message = $_[0];
	my $smtp = Net::SMTP::SSL->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 1);
	$smtp->auth($smtpuser,$smtppassword);
	$smtp->mail($mailfrom);
	$smtp->to($mailto);
	$smtp->recipient($mailto);
	$smtp->data();
	$smtp->datasend("To: $mailto\n");
	$smtp->datasend("From: $mailfrom\n");
	$smtp->datasend("Subject: $subject\n");
	$smtp->datasend("\n"); # done with header
	$smtp->datasend($message);
	$smtp->dataend();
	
	$smtpcode = $smtp->code();
	$smtpmsg = $smtp->message();
	
	$smtp->quit(); # all done. message sent.
	logentry ( "Mail send result: $smtpcode: $smtpmsg" );
}

sub logentry () {
	my $entry = $_[0];
	print STDOUT "$entry\n";
	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	$now = "$year-$month-$day-$hour:$min:$sec";
	print LOG $now; 
	print LOG ": $entry\n"; 
}

