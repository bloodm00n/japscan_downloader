#!/usr/bin/ruby

require 'fileutils'
require 'open-uri'
require 'net/http'

#require 'pp'

require 'thread'

class Manga

  attr_reader :chap, :chap_src  #, :page
  attr_accessor :folder

  def initialize(url, folder="")

    @page = open(url).readlines
    @chap = Array.new
    @folder = (folder == "") ? "./" + url.gsub(/http:\/\/.*mangas\//,"").gsub(/\//,"").gsub(/-/,"_") : folder

  end

  def get_chap

    @page.each do |l|
      if l.match(/^ *<a href=\"\/\/www.japscan.com\/lecture-en-ligne/)
        temp = l.gsub(/.*=\"/,"").gsub(/\".*/,"")
        @chap.push(temp)
      end

    end
    puts ""
    @chap.map.with_index { |x, i| puts "#{i}\t -> #{x.gsub(/.*\/([-_A-Za-z0-9\.]+)\/$/,'\1')}" }
    puts "\n\nFound " +  @chap.length.to_s + " file(s) to download:"
    puts "  from #{@chap.first.chomp.gsub(/.*\/([a-zA-Z0-9\.]+)\/$/,'\1')} to #{@chap.last.chomp.gsub(/.*\/([a-zA-Z0-9\.]+)\/$/,'\1')}\n\n\n"

  end
  
  def create_folder

    if File.directory?(@folder)
      puts "Warning: #{@folder} directory already exists" unless File.directory?(@folder)
    end
    FileUtils.mkdir_p(@folder)
    puts "Downloading manga to folder" + @folder + "\n\n"

  end

  def download_chapter(idx)

    chapter = @chap[idx]
    if chapter.match(/.*\/volume.*[0-9\.]+\//)
      chap = chapter.gsub(/.*\/volume-([0-9\.]+)\//,'\1')
    else
      chap = chapter.gsub(/.*\/([0-9\.]+)\//,'\1')
    end
    chap = (chap.match(/\./))? "%05.1f" % chap : "%03d" % chap
    if chapter.match(/.*\/volume.*[0-9\.]+\//)
      chap = "vol." + chap.to_s
    else
      chap = "ch." + chap.to_s
    end

    chap_path = @folder + "/" + chap
    #if Dir.exists?(chap_path) == true
    #  puts "Warning: Chapter #{chapter} already exist in " + @folder + " -> skipping"
    #  return
    #els
    if File.exists?("#{chap_path}.cbz") == true
      puts "Warning: Archive #{chap_path}.cbz already exist in " + @folder + " -> skipping"
      return
    end
    img_src = Array.new
    page = open("http:" + chapter).readlines
    page.each do |l|
      if l.match(/data-img.*<\/option>/)
        img_src.push(get_img_src(l.gsub(/.*value=\"/,"").gsub(/\".*/,"").chomp))
      end
    end
    chap_path = @folder + "/" + chap
    FileUtils.mkdir_p(chap_path)
    puts "Chapter " + chap
    i = 0
    print "-> downloading file "
    img_src.each do |url|
      i+=1

      filename = chap_path + "/" + File.basename(url)
      print "\r"
      stream = " -> downloading file "+ i.to_s + "/" + img_src.length.to_s
      print stream
      open(filename.chomp, 'w') do |file|
        if check_url(url) == true
          file.write(open(url).read)
          file.close
        else
          puts "\nWarning : did not found url " + url
        end
      end
    end
    puts "   => complete"
    puts "Producing file #{chap_path}.cbz" 
    `zip -rj "#{chap_path}.cbz" "#{chap_path}"`
    FileUtils.rm_r chap_path

  end

  def get_img_src(url)

    page = open("http://www.japscan.com" + url).readlines
    page.each do |l|
      if l.match(/<img/)
        return l.gsub(/.*src=\"/,"").gsub(/\".*/,"")
        break
      end
    end
  end
  
end

def get_manga_list

  list = Array.new  
  manga_page = open("http://www.japscan.com/mangas/").readlines
  manga_page.each do |l|
    next unless l.valid_encoding?
    if l.match(/^ *<div class=\"cell\"><a href=\"\/mangas\//)
      list.push(l.gsub(/.*=\"\/mangas\//,"").gsub(/\/\".*/,""))
    end
  end
  return list

end

def search_menu

  puts "Please enter search word (or regexp)"
  getted = gets.chomp
  puts "\nSearch Results:"
  list_res = $manga_list.select { |x| x.match(/#{getted}/) }
  puts "- no results" unless list_res != ""
  puts list_res
  puts ""
  begin 
    puts "1 > Download manga"
    puts "2 > Search again"
    puts "3 > Main menu"
    getted = gets.chomp.to_i
  end while getted != 1 && getted != 2 && getted != 3
  puts ""
  case getted
  when 1
    download_menu
  when 2
    search_menu
  when 3
    main_menu
  end

end

def check_url(url)
  return (Net::HTTP.get_response(URI.parse(url)).code == '200')
end

def download_menu

  res = 0
  begin
    puts "Enter full manga name" 
    manga_name = gets.chomp
    url = "http://www.japscan.com/mangas/" + manga_name + "/"
  end while check_url(url) == false

  mymanga = Manga.new(url)
  mymanga.get_chap

  puts "Please enter chapters to download (all/X/Y-Z)"
  flag = 0
  idx_l = 0
  idx_h = 0 
  begin 
    getted = gets.chomp
    if getted == "all" || getted == "a"
      idx_l = 0
      idx_h = mymanga.chap.length-1
      flag = 2
    elsif getted.match(/[0-9]+\-[0-9]+/)
      idx_l = getted.gsub(/\-[0-9]+/,"").to_i
      idx_h = getted.gsub(/[0-9]+\-/,"").to_i
      flag = 3
    elsif getted.match(/[0-9]+/)
      idx_l = getted.to_i
      idx_h = getted.to_i
      flag = 3
    else
      download_menu
    end
    raise "Error: chapter #{idx_h} should be <= #{mymanga.chap.length}" unless idx_h <= mymanga.chap.length-1
    raise "Error: chapter #{idx_l} should be >= 0" unless idx_l >= 0
  end while flag == 0

  # Creating queue structure that represent set of work tbd (queue is Thread Safe)
  work_q = Queue.new

  # filing work queue with index
  (idx_l..idx_h).to_a.each{|x| work_q.push x }

  # pool of 4 threads
  workers = (0..3).map do
    # starting thread
    Thread.new do
      begin
        while x = work_q.pop(true)
          mymanga.download_chapter(x)
        end
        # handling exception, here if work_q is empty
      rescue ThreadError
      end
    end
  end
  # joining the main thread of execution with the worker thread
  workers.map(&:join)
    
end

def main_menu

  begin 
    puts "1 > List all mangas"
    puts "2 > Search Manga (regexp)"
    puts "3 > Download Manga"
    puts "4 > Exit"
    getted = gets.chomp.to_i
  end while getted != 1 && getted != 2 && getted != 3 && getted != 4
  case getted
  when 1
    puts $manga_list
    puts ""
    main_menu
  when 2
    search_menu
  when 3
    download_menu
  when 4
    exit
  end

end

$manga_list = get_manga_list
main_menu

