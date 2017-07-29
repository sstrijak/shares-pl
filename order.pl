#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw( Date_to_Days );
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;

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
my $broker = 19.95;
my $date = "";
my $action = "";
my $code = "";
my $issues = 0;
my $price = 0;
my $oldissues = 0;
my $investment = 0;
my $perissue = 0;
my $amount = 0;
my $consideration = 0;
my $profit = 0;

open LOG, ">>", $logfile;

########## Read parameters and display help message
if ( defined ( $ARGV[0] ) ) { $date = $ARGV[0]; }
if ( defined ( $ARGV[1] ) ) { $action = $ARGV[1]; }
if ( defined ( $ARGV[2] ) ) { $code = $ARGV[2]; }
if ( defined ( $ARGV[3] ) ) { $issues = $ARGV[3]; }
if ( defined ( $ARGV[4] ) ) { $price = $ARGV[4]; }
if ( defined ( $ARGV[5] ) ) { $broker = $ARGV[5]; }

if ( $date eq "" or $date eq "?" or $date eq "-?" or $date eq "-h") {
	print "Usage: perl order.pl <YYYY-MM-DD> <buy/sell> <COD> <issues> <price> [<broker>]\n";
	exit;
}

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
	# get current investment
	$sql = "select issues, investment from portfolio where code='$code'";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	if (@row = $sth->fetchrow_array())
	{
		$oldissues = $row[0];
		$investment = $row[1];
	}
	$sth->finish();

	# Check the order
	$consideration = $issues * $price;
	if ( $action eq "sell" )
	{
		if ( $issues > $oldissues ) {
			$thismessage = "Trying to sell $issues of $code, more than $oldissues we have";
			logentry ( $thismessage );
			$message .= "$thismessage\n";
			$keepgoing = 0;
		} else {
			$amount = $consideration - $broker;
			$investedperissue = $investment / $oldissues;
			$invested = $investedperissue * $issues;
			$profit = $consideration - $invested;
			if ( $profit > 0 ) { $thismessage = "+++ $profit selling $issues of $code, congratulations!"; }
			elsif ( $profit > 0 ) { $thismessage = "--- $profit selling $issues of $code, good lucK next time!"; }
			else { $thismessage = "    on the money selling $issues of $code, good luc next time!"; }
			logentry ( $thismessage );
			$message .= "$thismessage\n";
		}
	}
	else {
		$amount = $consideration + $broker;
	}
}
if ($keepgoing)
{
	# Record the order
	$sql = "INSERT IGNORE INTO `orders` SET date='$date', action='$action', code='$code', issues=$issues, price=$price, broker=$broker, consideration=$consideration, amount=$amount, profit=$profit";
	print "$sql\n";
	$dbh->do( $sql );
	$error = $dbh->{'mysql_error'};
	if ( $error )
	{
		$thismessage = "Error recording the order: $error";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	}
	$sth->finish();
}

if ($keepgoing)
{
	# Update portfolio
	if ( $action eq "buy" )
	{ 
		$investment = $investment + $amount + $broker;
		$issues = $oldissues + $issues;
	}
	else
	{
		$issues = $oldissues - $issues;
		$investment = $issues * $investedperissue;
	}
	
	if ( $issues )
	{
		if ( $oldissues ){ $sql = "update `portfolio` SET issues=$issues, investment=$investment where code='$code'"; }
		else { $sql = "INSERT IGNORE INTO `portfolio` SET code='$code', issues=$issues, investment=$investment"; }
	} else { $sql = "delete from `portfolio` where code='$code'"; }
	$dbh->do( $sql );
	$error = $dbh->{'mysql_error'};
	if ( $error )
	{
		$thismessage = "Error updating portfolio: $error";
		logentry ( $thismessage );
		$message .= "$thismessage\n";
		$keepgoing = 0;
	}
	$sth->finish();
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

