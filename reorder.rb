require 'net/http'
require 'net/https'
require 'json'
require 'thor'

class ReorderCircle < Thor
  CIRCLE_API = 'https://circleci.com/api/v1'

  desc "vib BUILD_NUMBER", "Move BUILD_NUMBER to the top of the queue"
  def vib(build_number, debug = false)
    build_number = build_number.to_i
    @debug = !!debug

    unless File.file?("#{ENV['HOME']}/.circle_token")
      puts "Please create ~/.circle_token containing your Circle API token"
      return 1
    end

    circle_token = File.read("#{ENV['HOME']}/.circle_token")

    puts "Fetching queued builds..."
    res = get("#{CIRCLE_API}/project/mavenlink/mavenlink?circle-token=#{circle_token}&limit=100&offset=0")
    puts "Response HTTP Status Code: #{res.code}" unless res.code.to_i == 200

    builds = JSON.parse(res.body)

    puts "Finding your build..."
    scheduled = builds.select { |build| build["status"] == "scheduled" || build["status"] == "not_running" }
    my_build = builds.select { |build| build["build_num"] == build_number }

    if my_build.empty?
      puts "Couldn't find your build ##{build_number}"
      puts builds
      return 1
    end

    my_build = my_build.first

    puts "Re-enqueueing builds ahead of yours..."
    scheduled.each do |build|
      if build["build_num"] < my_build["build_num"]
        res = post("#{CIRCLE_API}/project/mavenlink/mavenlink/#{build["build_num"]}/cancel?circle-token=#{circle_token}")

        if res.code.to_i == 200
          res = post("#{CIRCLE_API}/project/mavenlink/mavenlink/#{build["build_num"]}/retry?circle-token=#{circle_token}")
          puts "Failed to retry build ##{build["build_num"]}: #{build["build_url"]}" unless res.code.to_i == 200
        else
          puts "Failed to cancel build ##{build["build_num"]}: #{build["build_url"]}"
        end
      end
    end

    puts "Done"
  end

  private

  def http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http
  end

  def get(req)
    uri = URI(req)
    req =  Net::HTTP::Get.new(uri)
    http(uri).request(req)
  end

  def post(req)
    if @debug
      puts "pretending to POST to: #{req}"
      return FakeResponse.new
    end

    uri = URI(req)
    req =  Net::HTTP::Post.new(uri)
    http(uri).request(req)
  end
end

class FakeResponse
  def code
    200
  end
end

ReorderCircle.start(ARGV)
