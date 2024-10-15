require "nokogiri"
require "open-uri"
require "lightly"

Lightly.life = "24h"

module Pubid::Nist
  class NistTechPubs
    @converted_id = @converted_doi = {}

    class << self

      attr_accessor :documents, :converted_id, :converted_doi

      def fetch
        Lightly.prune
        @documents ||= Lightly.get "documents" do
          LocMods::Collection.from_xml(OpenURI.open_uri(RelatonNist::DataFetcher::URL)).mods.map do |doc|
            bib_item = RelatonNist::ModsParser.new(doc, SERIES["long"]).parse
            bib_item.docidentifier.map do |doc|
              doc.type == "NIST" ? [:id, doc.id] : [doc.type.downcase.to_sym, doc.id.gsub("10.6028/", "")]
            end.to_h.merge({ title: bib_item.title.first.title })
          end
        end
      rescue StandardError => e
        warn e.message
        []
      end

      def convert(doc)
        id = @converted_id[doc[:id]] ||= Pubid::Nist::Identifier.parse(doc[:id])
        return id unless doc.key?(:doi)

        begin
          doi = @converted_doi[doc[:doi]] ||=
            Pubid::Nist::Identifier.parse(doc[:doi])
        rescue Pubid::Core::Errors::ParseError
          return id
        end
        # return more complete pubid
        id.merge(doi)
      rescue Pubid::Core::Errors::ParseError
        @converted_doi[doc[:doi]] ||= Pubid::Nist::Identifier.parse(doc[:doi])
      end

      def parse_docid(doc)
        id = doc.at("publisher_item/item_number", "publisher_item/identifier")
               &.text&.sub(%r{^/}, "")
        if id == "NBS BH 10"
          # XXX: "doi" attribute is missing for doi_data
          doi = "NBS.BH.10"
        else
          doi = doc.at("doi_data/doi").text.gsub("10.6028/", "")
        end

        title = doc.at("titles/title").text
        title += " #{doc.at('titles/subtitle').text}" if doc.at("titles/subtitle")
        case doi
        when "10.6028/NBS.CIRC.12e2revjune" then id.sub!("13e", "12e")
        when "10.6028/NBS.CIRC.36e2" then id.sub!("46e", "36e")
        when "10.6028/NBS.HB.67suppJune1967" then id.sub!("1965", "1967")
        when "10.6028/NBS.HB.105-1r1990" then id.sub!("105-1-1990", "105-1r1990")
        when "10.6028/NIST.HB.150-10-1995" then id.sub!(/150-10$/, "150-10-1995")
        end

        { id: id || doi, doi: doi, title: title }
      end

      def comply_with_pubid
        fetch.select do |doc|
          convert(doc).to_s == doc[:id]
        rescue Pubid::Core::Errors::ParseError
          false
        end
      end

      def different_with_pubid
        fetch.reject do |doc|
          convert(doc).to_s == doc[:id]
        rescue Pubid::Core::Errors::ParseError
          true
        end
      end

      def parse_fail_with_pubid
        fetch.select do |doc|
          convert(doc).to_s && false
        rescue Pubid::Core::Errors::ParseError
          true
        end
      end

      # returning current document id, doi, title and final PubID
      def status
        fetch.lazy.map do |doc|
          final_doc = convert(doc)
          {
            id: doc[:id],
            doi: doc[:doi],
            title: doc[:title],
            finalPubId: final_doc.to_s,
            mr: final_doc.to_s(:mr),
          }
        rescue Pubid::Core::Errors::ParseError
          {
            id: doc[:id],
            doi: doc[:doi],
            title: doc[:title],
            finalPubId: "parse error",
            mr: "parse_error",
          }
        end
      end
    end
  end
end
