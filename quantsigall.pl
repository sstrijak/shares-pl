#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw( Date_to_Days );
use Date::Calc qw(English_Ordinal);
use Date::Calc qw(Month_to_Text);
use Date::Calc qw(Add_Delta_Days);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
use LWP::UserAgent;
use HTTP::Request::Common qw{ POST };
use HTTP::Cookies;

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
my $dbtable = "quantsig";

# Quant Trader
my $quantuser = "sstrijak\@hotmail.com";
my $quantpass = "D3l3t312";

# Flow control and reporting
my $keepgoing = 1;

# Script data
my $lastdate;
my $lastyear;
my $lastmonth;
my $lastday;
my $ua;
my $cookie_jar;
my $daycount = 0;
my @signaldetails;

my $firstyear = 2014;
my $firstmonth = 11;
my $firstday = 17;

$quantlogin_url = "http://portphillippublishing.com.au/login/";
$quantsig_url = "http://portphillippublishing.com.au/signal/";

########## Start

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
	$ua = LWP::UserAgent->new;
	$cookie_jar = HTTP::Cookies->new;

	my $request = POST( $quantlogin_url, [
		'log' => $quantuser,
		'pwd' => $quantpass,
		'cf_login_action' => 'login',
		'cf_form_name' => 'header',
		'redirect_to' => '/qua/'
	] );

	$response = $ua->request( $request );
	$cookie_jar->extract_cookies( $response );
	$ua->cookie_jar( $cookie_jar );

	# Chec that login is successful
	$loc = $response->headers->header("location");

	if ( $loc ne "http://portphillippublishing.com.au/qua/")
	{
		$keepgoing = 0;
	}
}

$year = 2014;
$month = 12;
$day = 3;
	
while ( $keepgoing )
{
	print "$year-$month-$day\n";
	$quantday = English_Ordinal($day);
	$quantmonth = Month_to_Text($month);
	$quantdate = $quantmonth."-".$quantday."-".$year."/";
	$response = $ua->get($quantsig_url.$quantdate);
	$content = $response->content();
		
	if ( $content )
	{
		$signal=0; 
		$signalline=0; 
		
		$signaldetails[1] = "";
		$signaldetails[2] = "";
		$signaldetails[3] = "";
		$signaldetails[4] = "";
		$signaldetails[5] = "";

		@contentlines = split ('\n', $content);
		foreach $line ( @contentlines )
		{
			if ( $line =~ /Our Apologies, but the page you requested could not be found/ )
			{
				print "No signals this day\n";
			}
			if ( $line =~ /There  are no entry/ )
			{
				print "No entry signals\n";
			}
			if ( $line =~ /There are no entry/ )
			{
				print "No entry signals\n";
			}
			
			if ( $line =~ /<h1>Signals/ )
			{
				$signaltable = 1 ;
				$signalline = 0;
			}
			if ( $line =~ /Exit summary/ )
			{
				$signaltable = 0 ;
				$exittable = 1 ;
				$signalline = 0;
			}
			
			if ( $line =~ /<\/table>/ )
			{
				$signaltable = 0 ;
				$exittable = 0 ;
				$signalline = 0;
			}
			if ( $line =~ /<\/tr>/ )
			{
				if ( $signaltable) {
					if ( $signalline > 0)
					{
						$order = lc($signaldetails[1]);
						$code = $signaldetails[2];

						$name = "";
						$signalno = $signaldetails[3];
						$exit = $signaldetails[4];
						$close = $signaldetails[5];

						#$name = $signaldetails[3];
						#$signalno = $signaldetails[4];
						#$exit = $signaldetails[5];
						#$close = $signaldetails[6];
						
						print "entry $order $code\n";
						$sql = "INSERT IGNORE INTO `quantsig` SET `code` = '$code',`date` = '$year-$month-$day',`order` = '$order',`name` = '$name',`signal` = '$signalno',`exit` = '$exit'";
						$dbh->do( $sql );
						$error = $dbh->{'mysql_error'};
						$signaldetails[1] = "";
						$signaldetails[2] = "";
						$signaldetails[3] = "";
						$signaldetails[4] = "";
						$signaldetails[5] = "";
						$signaldetails[6] = "";
					}
					$signalline=1; 
				}
				if ( $exittable) {
					if ( $signalline > 0)
					{
						$pos = lc($signaldetails[1]);
						$code = $signaldetails[2];
						$name = $signaldetails[3];
						print "exit $pos $code\n";
						$sql = "INSERT IGNORE INTO `quantexit` SET `date` = '$year-$month-$day',`position` = '$pos',`code` = '$code',`name` = '$name'";
						$dbh->do( $sql );
						$error = $dbh->{'mysql_error'};
						$signaldetails[1] = "";
						$signaldetails[2] = "";
						$signaldetails[3] = "";
					}
					$signalline=1; 
				}
			}
			if ( $line =~ /<td.*>(.+)<\/td>/ )
			{
				$line = $1 ;
				if ( $line =~ /<strong>(.*)/ ) { $line = $1 ; }
				if ( $line =~ /(.*)<\/strong>/ ) { $line = $1 ; }
				if ( $signalline )
				{
					$signaldetails[$signalline] = $line;
					$signalline++;
				}
			}
		}
	}
	if ( $year <= $firstyear and $month <= $firstmonth and $day <= $firstday)
	{
		$keepgoing = 0;
	}
	($year,$month,$day) = Add_Delta_Days($year,$month,$day, -1);
}

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

