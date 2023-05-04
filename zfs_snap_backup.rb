require 'open3'
require 'json'

config = JSON.parse(File.read(ARGV[0]))

snapshots = {}

`zfs list -t snapshot | grep zfs-auto-snap`.lines.each do |l|
  snap = l.split.first
  fs,tag = snap.split('@')
  time = tag.gsub('zfs-auto-snap_','').split('-').first
  if(time == 'monthly' || time == 'daily')
    snapshots[fs] ||= []
    snapshots[fs] << snap
  end
end

existing = {}
`aws s3 ls keep-backup --no-paginate --recursive`.lines.each do |l|
  name = l.split.last.strip
  existing[name] = true
end

filesystems = config['filesystems'] || snapshots.keys

filesystems.each do |fs|
  snaps = snapshots[fs]
  monthly = nil
  previous = nil

  next unless snaps

  snaps.each do |snap|

    tag = snap.split('@').last
    time = tag.gsub('zfs-auto-snap_','').split('-').first

    if(time == 'monthly' || previous.nil?)
      command = "sudo zfs send -c -L -e #{snap}"
      monthly = snap
    elsif(previous)
      command = "sudo zfs send -c -L -e -i #{previous} #{snap}"
    end

    if command && existing[snap.gsub('@','/')].nil?
      out,st = Open3.capture2(command+' -n -P | grep size')
      size = out.split.last.to_i

      s3_command = "aws s3 cp - s3://#{config['bucket']}/#{snap.gsub('@','/')} --expected-size #{size} --storage-class STANDARD_IA" # DEEP_ARCHIVE

      puts "Sending #{snap}..."
      system("#{command} | #{s3_command}")
    end

    previous = snap
  end
end


