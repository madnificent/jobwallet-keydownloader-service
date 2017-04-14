require 'open-uri'

get '/fetch' do
  content_type 'application/json'

  location = params['location']
  doc = Nokogiri::HTML( fetch_url params['location'] )

  wallets = fetch_rels(doc, "jobwallet").map do |wallet_location|
    normalized_uri = URI::join location, wallet_location
    store_remote_file normalized_uri, "wallet"
  end
  keys = fetch_rels(doc, "pubkey").map do |pubkey_location|
    normalized_uri = URI::join location, pubkey_location
    store_remote_file normalized_uri, "pubkey"
  end

  {
    data: {
      attributes: {
        wallets: wallets,
        keys: keys
      }
    }
  }.to_json
end


## Fetches all relations of a given type from a parsed document
def fetch_rels( nokogiri_document, relation, attr="href" )
  nokogiri_document.css("link[rel=#{relation}]").map do |element|
    element.attribute(attr).value
  end
end


## Helper for fetching a URL
def fetch_url( url )
  # See http://stackoverflow.com/questions/27407938/ruby-open-uri-redirect-forbidden#27411667
  uri = url.class == String ? URI.parse(url) : url
  tries = 3

  begin
    uri.open(redirect: false)
  rescue OpenURI::HTTPRedirect => redirect
    uri = redirect.uri # assigned from the "Location" response header
    retry if (tries -= 1) > 0
    raise
  end
end

def write_to_file( content, base="wallet-data" )
  base ||= "wallet-data"
  rel_filename = "#{base}-#{generate_uuid}"
  full_path = "/fileshare/wallets/#{rel_filename}"

  File.write( full_path, content )

  "fileshare://#{rel_filename}"
end

def store_remote_file( uri, base_filename )
  content = fetch_url uri
  pathname = write_to_file( content, base_filename )

  { uri: uri, pathname: pathname }
end
