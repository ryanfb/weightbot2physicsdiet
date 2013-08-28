#!/usr/bin/env ruby

require 'rubygems'
require 'mechanize'
require 'csv'
require 'date'
require 'yaml'

# From: http://gmarik.info/blog/2010/10/16/scraping-asp-net-site-with-mechanize
class Mechanize::Page::Link
  def asp_link_args
    href = self.attributes['href']
    href =~ /\(([^()]+)\)/ && $1.split(/\W?\s*,\s*\W?/).map(&:strip).map {|i| i.gsub(/^['"]|['"]$/,'')}
  end

  def asp_click(action_arg = nil)
    etarget,earg = asp_link_args.values_at(0, 1)

    f = self.page.form_with(:name => 'aspnetForm')
    f.action = asp_link_args.values_at(action_arg) if action_arg
    f['__EVENTTARGET'] = etarget
    f['__EVENTARGUMENT'] = earg
    f.submit
  end
end

config = YAML.load_file('config.yml')

agent = Mechanize.new

page = agent.get('http://physicsdiet.com/')

page = agent.page.link_with(:text => 'Fitness Log').click

login_form = page.forms_with(:action => 'FitnessLog.aspx').first
login_form.field_with(:type => 'text').value = config['physicsdiet_username']
login_form.field_with(:type => 'password').value = config['physicsdiet_password']

physicsdiet_page = agent.submit(login_form, login_form.buttons.first)

csv_page = agent.get('http://physicsdiet.com/FitnessLog.aspx?f=csv')
physicsdiet_csv = CSV.parse(csv_page.body, :headers => true)

physicsdiet = {}

physicsdiet_csv.each do |row|
  date = Date.strptime(row['Date'],"%m/%d/%Y")
  physicsdiet[date] = row[' Weight']
end

page = agent.get('http://weightbot.com/')

weightbot_form = page.forms_with(:action => '/account/login').first
weightbot_form.email = config['weightbot_email']
weightbot_form.password = config['weightbot_password']

page = agent.submit(weightbot_form, weightbot_form.buttons.first)

export_form = page.forms_with(:action => '/export').first
page = agent.submit(export_form, export_form.buttons.first)

weightbot_csv = CSV.parse(page.body, :headers => true)

weightbot = {}

weightbot_csv.each do |row|
  date = Date.parse(row['date'])
  weightbot[date] = row[' pounds'].to_f
end

weightbot.each_pair do |date, weight|
  unless physicsdiet.has_key?(date)
    date_string = date.strftime("%m/%d/%Y")
    puts "Setting weight for #{date_string} to #{weight}"
    physicsdiet_update_form = physicsdiet_page.forms_with(:action => 'FitnessLog.aspx').first
    physicsdiet_update_form['ctl00$ctl00$MainContentPlaceholder$MainContentPlaceholder$LoginView1$WeightEntryEditor$Date'] = date_string
    physicsdiet_update_form['ctl00$ctl00$MainContentPlaceholder$MainContentPlaceholder$LoginView1$WeightEntryEditor$Weight'] = weight.to_s
    physicsdiet_update_form.add_field!('ctl00_ctl00_MainContentPlaceholder_MainContentPlaceholder_LoginView1_WeightEntryEditor_SaveLink','ctl00$ctl00$MainContentPlaceholder$MainContentPlaceholder$LoginView1$WeightEntryEditor$SaveLink')
    physicsdiet_page = physicsdiet_page.link_with(:text => 'Add Entry').asp_click
  end
end
