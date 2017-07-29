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
my $second = "";
my $start = "";
my $end = "";

open LOG, ">>", $logfile;

if ( defined ( $ARGV[0] ) ) { $code = $ARGV[0]; }
if ( defined ( $ARGV[1] ) ) { $second = $ARGV[1]; }
if ( defined ( $ARGV[2] ) ) { $start = $ARGV[2]; }
if ( defined ( $ARGV[3] ) ) { $end = $ARGV[3]; }

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
	$sql = "select date, close, $second from daily where code='$code' and date >= '$start' and date <= '$end'";
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
		title             => "$code vs $second",
		transparent       => 0,
		fgclr             => [qw(black)],
		dclrs             => [qw(lgray blue)],
		y_number_format   => '%0.2f',
#			x_label_skip      => 5,
		long_ticks        => 1,
	) or warn $graph->error;
	$graph->set_legend("$code", "$second");

	$graph->plot(\@data) or die $graph->error;

	my $file = "graphs-$code-$second.png";
	open(my $out, '>', $file) or die "Cannot open '$file' for write: $!";
	binmode $out;
	print $out $graph->gd->png;
	close $out;
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

