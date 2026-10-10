#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Basename;

my $tools = "/home/ztg/tools";
make_path($tools);
chdir($tools) or die $!;

sub download {
  my ($url, $out) = @_;
  return if -f $out && -s $out > 1000;
  print "Downloading $url\n";
  # Prefer curl/wget if present, else pure perl
  if (system("command -v curl >/dev/null 2>&1") == 0) {
    system("curl", "-L", "--retry", "3", "-o", $out, $url) == 0 or die "curl failed";
  } elsif (system("command -v wget >/dev/null 2>&1") == 0) {
    system("wget", "-O", $out, $url) == 0 or die "wget failed";
  } else {
    # HTTP::Tiny is core in modern perl
    require HTTP::Tiny;
    my $http = HTTP::Tiny->new(timeout => 600, max_redirect => 10);
    my $res = $http->mirror($url, $out);
    die "download failed: $res->{status} $res->{reason}\n" unless $res->{success} || ($res->{status}==304);
  }
  print "Saved $out (", -s $out, " bytes)\n";
}

# Portable x86_64 linux gcc toolchain (glibc) from musescore / crosstool alternatives:
# Use official gcc release built for x86_64-linux-gnu from bootlin or similar.
# Bootlin toolchains: https://toolchains.bootlin.com/
# Use a known good x86_64 toolchain with glibc.
my $tc_url = "https://toolchains.bootlin.com/downloads/releases/toolchains/x86-64/tarballs/x86-64--glibc--stable-2024.05-1.tar.bz2";
my $tc_tar = "x86-64-glibc-toolchain.tar.bz2";
download($tc_url, $tc_tar);

if (!-d "x86_64-buildroot-linux-gnu" && !-d "x86-64--glibc--stable-2024.05-1") {
  print "Extracting toolchain...\n";
  system("tar", "-xjf", $tc_tar) == 0 or die "tar extract failed: $?";
}

# Find g++
my $gxx = "";
for my $cand (glob("*/bin/x86_64-linux-g++"), glob("*/bin/x86_64-*-g++"), glob("*/bin/g++")) {
  if (-x $cand) { $gxx = "$tools/$cand"; last; }
}
# also nested
if (!$gxx) {
  open my $fh, "-|", "find", $tools, "-type", "f", "-name", "*-g++", "-perm", "-111" or die $!;
  while (<$fh>) { chomp; $gxx = $_; last; }
  close $fh;
}
die "g++ not found in toolchain\n" unless $gxx && -x $gxx;
print "Using $gxx\n";
system($gxx, "--version");

my $ROOT = "/mnt/c/Users/ztg/Desktop/lunwen/lunwen/sim";
my $NATIVE = "$ROOT/native";
my $BIN = "$ROOT/godot/bin/linux-x86_64";
my $SYSROOT = "$ROOT/third_party/sysroot/usr";
my $GODOT_CPP = "$ROOT/third_party/godot-cpp";
my $GEN = "$NATIVE/build/godot-cpp/gen/include";
my $GODOT_LIB = "$NATIVE/build/bin/libgodot-cpp.linux.template_debug.x86_64.a";
die "missing godot lib\n" unless -f $GODOT_LIB;

my @inc = (
  "-I$GODOT_CPP/include",
  "-I$GODOT_CPP/gen/include",
  "-I$GODOT_CPP/gdextension",
  "-I$GEN",
  "-I$NATIVE/src",
);
my @flags = ("-std=c++17", "-O2", "-fPIC", "-DNDEBUG");

print "=== compile bridge ===\n";
system($gxx, @flags, @inc, "-c", "$NATIVE/src/auto_aim_bridge.cpp", "-o", "/tmp/auto_aim_bridge.o") == 0 or die "bridge compile failed";
system($gxx, @flags, @inc, "-c", "$NATIVE/src/register_types.cpp", "-o", "/tmp/register_types.o") == 0 or die "register compile failed";

print "=== link libsp_vision_sim.so ===\n";
system($gxx, "-shared", "-o", "$BIN/libsp_vision_sim.so",
  "/tmp/auto_aim_bridge.o", "/tmp/register_types.o", $GODOT_LIB,
  "-ldl", "-lpthread",
  "-Wl,-rpath,\$ORIGIN:\$ORIGIN/runtime") == 0 or die "bridge link failed";

print "=== compile worker ===\n";
system($gxx, @flags, "-I$NATIVE/src", "-I$SYSROOT/include",
  "-c", "$NATIVE/src/worker_main.cpp", "-o", "/tmp/worker_main.o") == 0 or die "worker compile failed";

print "=== link sp_vision_worker ===\n";
system($gxx, "-o", "$BIN/sp_vision_worker", "/tmp/worker_main.o",
  "-L$BIN", "-lsp_vision_engine",
  "-L$SYSROOT/lib", "-lyaml-cpp",
  "-Wl,-rpath,\$ORIGIN:\$ORIGIN/runtime",
  "-Wl,-rpath-link,$BIN:$BIN/runtime:$SYSROOT/lib") == 0 or die "worker link failed";

print "=== verify multi-robot marker ===\n";
my $ok = system("grep", "-aF", "multi-robot", "$BIN/sp_vision_worker") == 0;
print $ok ? "OK multi-robot present\n" : "WARN multi-robot missing\n";
system("ls", "-la", "$BIN/libsp_vision_sim.so", "$BIN/sp_vision_worker");
print "REBUILD DONE\n";
