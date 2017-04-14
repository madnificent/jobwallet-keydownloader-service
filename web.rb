# see https://github.com/mu-semtech/mu-ruby-template for more info
get '/' do
require 'open-uri'
  content_type 'application/json'
  { data: { attributes: { hello: 'world' } } }.to_json
def fetch_rels( nokogiri_document, relation, attr="href" )
  nokogiri_document.css("link[rel=#{relation}]").map do |element|
    element.attribute(attr).value
  end
end

def fetch_url( url )
  # See http://stackoverflow.com/questions/27407938/ruby-open-uri-redirect-forbidden#27411667
  uri = URI.parse(url)
  tries = 3

  begin
    uri.open(redirect: false)
  rescue OpenURI::HTTPRedirect => redirect
    uri = redirect.uri # assigned from the "Location" response header
    retry if (tries -= 1) > 0
    raise
  end
end
