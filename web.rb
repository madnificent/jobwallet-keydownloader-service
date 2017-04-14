require 'open-uri'

post "/delta" do
  request.body.rewind
  payload = JSON.parse request.body.read

  created_entities = []

  payload["delta"].each do |delta|
    if delta["graph"] == "http://mu.semte.ch/application"
      delta["inserts"].map do |insert|
        is_type_declaration = insert["p"]["value"] == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        is_authorative_body = insert["o"]["value"] == "http://mu.semte.ch/vocabularies/ext/AuthorativeBody"
        if is_type_declaration and is_authorative_body
          created_entities << insert["s"]["value"]
        end
      end
    end
  end

  found_entities = created_entities.map do |authorative_body_uri|
    unless authorative_body_is_fetched? authorative_body_uri
      log.info "Fetching authorative body #{authorative_body_uri}"
      fetch_authorative_body_info authorative_body_uri, false
    end
  end

  if found_entities.length > 0
    log.info "Found #{found_entities.size} authorative bodies"
    log.info found_entities.to_json
  end

  return 204
end

get %r{fetch/?} do
  content_type 'application/json'

  location = params['location']

  creation_info = fetch_authorative_body_info location

  { data: { attributes: creation_info } }.to_json
end

## Returns truethy if the authorative body was fetched before
def authorative_body_is_fetched?( authorative_body )
  query <<SPARQL
    PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
    PREFIX mu: <http://mu.semte.ch/vocabularies/core/>

    ASK {
      GRAPH <#{settings.graph}> {
        <#{authorative_body}> ext:isFetched "true".
      }
    }
SPARQL
end

## Downloads the authorative body to fetch the necessary contents
def fetch_authorative_body_info( location, generate = true )
  doc = Nokogiri::HTML( fetch_url location )

  wallets = fetch_rels(doc, "jobwallet").map do |wallet_location|
    normalized_uri = URI::join location, wallet_location
    store_remote_file normalized_uri, "wallet"
  end
  keys = fetch_rels(doc, "pubkey").map do |pubkey_location|
    normalized_uri = URI::join location, pubkey_location
    store_remote_file normalized_uri, "pubkey"
  end

  authorative_body_data = <<TTL
    <#{location}> a ext:AuthorativeBody;
      ext:isFetched "true";
      ext:hasWallet #{wallets.map { |w| "<#{w[:uri]}>" }.join(",") };
      ext:hasPubkey #{keys.map { |k| "<#{k[:uri]}>" }.join(",") }.
TTL
  authorative_uuid = <<TTL
    <#{location} mu:uuid "#{generate_uuid}".
TTL

  wallets_data = wallets.map do |wallet|
    <<TTL
      <#{wallet[:uri]}> a ext:JobWallet;
        ext:hasFile <#{wallet[:pathname]}>;
        mu:uuid "#{generate_uuid}".
TTL
  end.join("\n")
  keys_data = keys.map do |key|
    <<TTL
      <#{key[:uri]}> a ext:PublicKey;
        ext:hasFile <#{key[:pathname]}>;
        mu:uuid "#{generate_uuid}".
TTL
  end.join("\n")

  update <<SPARQL
    PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
    PREFIX mu: <http://mu.semte.ch/vocabularies/core/>

    INSERT DATA {
      GRAPH <#{settings.graph}> {
 #{authorative_body_data}
 #{authorative_uuid if generate}
 #{wallets_data}
 #{keys_data}
      }
    }
SPARQL

  { wallets: wallets, keys: keys }

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
