# RD to HTML translate library for rdfmt.rb
# $Id: rd2html-lib.rb,v 1.53 2003/03/08 12:45:08 tosh Exp $

require 'cgi'
require 'rd/rdvisitor'
require 'rd/version'

module RD
  module HTMLTag
    def tag(name, **attrs)
      "#{tag_open name, **attrs}#{block_given? ? yield : ''}#{tag_close name}"
    end

    def tag_block(name, **attrs)
      inner = yield().flatten.compact.join("\n").chomp
      [tag_open(name, **attrs), inner, tag_close(name)].join("\n")
    end

    def tag_single(name, **attrs)
      tag_open name, ' />', **attrs
    end

    def tag_open(name, suffix = '>', **attrs)
      name = tag_name(name)
      if attrs.empty?
        "<#{name}#{suffix}"
      else
        "<#{name} #{tag_attrs(**attrs)}#{suffix}"
      end
    end

    def tag_close(name)
      "</#{tag_name name}>"
    end

    def tag_attrs(**pairs)
      pairs.map{|k, v| %Q`#{tag_name k}="#{v}"` }.join(' ')
    end

    def tag_name(raw_name)
      raw_name.to_s.tr('_', '-').downcase.intern
    end
  end

  class RD2HTMLVisitor < RDVisitor
    include HTMLTag
    include MethodParse

    SYSTEM_NAME = "RDtool -- RD2HTMLVisitor"
    SYSTEM_VERSION = "$Version: "+ RD::VERSION+"$" 
    VERSION = Version.new_from_version_string(SYSTEM_NAME, SYSTEM_VERSION)

    def self.version
      VERSION
    end

    # must-have constants
    OUTPUT_SUFFIX = "html"
    INCLUDE_SUFFIX = ["html"]

    METACHAR = { "<" => "&lt;", ">" => "&gt;", "&" => "&amp;" }

    attr_accessor :css
    attr_accessor :charset
    alias charcode charset
    alias charcode= charset=
    attr_accessor :lang
    attr_accessor :title
    attr_reader :html_link_rel
    attr_reader :html_link_rev
    attr_accessor :use_old_anchor
    # output external Label file.
    attr_accessor :output_rbl

    attr_reader :footnotes
    attr_reader :foottexts

    def initialize
      @css = nil
      @charset = nil
      @lang = nil
      @title = nil
      @html_link_rel = {}
      @html_link_rev = {}
      @footnotes = []
      @index = {}
      @use_old_anchor = true # MUST -> nil
      @output_rbl = nil
      super
    end

    def visit(tree)
      prepare_labels(tree, "label-")
      prepare_footnotes(tree)
      tmp = super(tree)
      make_rbl_file(@filename) if @output_rbl and @filename
      tmp
    end

    def apply_to_DocumentElement(element, content)
      [xml_decl(),
       doctype_decl(),
       html_open_tag(),
       html_head(),
       html_body(content),
       tag_close(:html), ''].join("\n")
    end

    private

    def document_title
      @title || @filename || document_title_by_input_filename() || 'Untitled'
    end

    def document_title_by_input_filename
      @input_filename == '-' ? nil : @input_filename
    end

    def xml_decl
      buf = ['xml', 'version="1.0"']
      buf << %Q`encoding="#{@charset}"` if @charset
      "<?#{buf.join ' '} ?>"
    end

    DOCTYPE = <<-EOS
<!DOCTYPE html
  PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    EOS

    def doctype_decl
      DOCTYPE
    end

    def html_open_tag
      attrs = {xmlns: 'http://www.w3.org/1999/xhtml'}
      if @lang
        attrs[:lang] = @lang
        attrs[:"xml:lang"] = @lang
      end
      tag_open :html, **attrs
    end

    def html_head
      [tag_open(:head),
       html_content_type(),
       html_title(),
       link_to_css(),
       forward_links(),
       backward_links(),
       tag_close(:head)].compact.join("\n")
    end

    def html_content_type
      return nil unless @charset
      tag_single :meta, http_equiv: 'Content-type', content: "text/html; charset=#{@charset}"
    end

    def html_title
      tag(:title){ document_title() }
    end

    def link_to_css
      return nil unless @css
      tag_single :link, href: @css, type: 'text/css', rel: 'stylesheet'
    end

    def forward_links
      header_links @html_link_rel, :rel
    end

    def backward_links
      header_links @html_link_rev, :rev
    end

    def header_links(list, attr)
      return nil if list.empty?
      list.sort_by(&:first).map{|val, href|
        tag_single :link, :href => href, attr => val
      }.join("\n")
    end

    def html_body(contents)
      tag_block(:body){ [contents, make_foottext()] }
    end

    public

    def apply_to_Headline(element, title)
      anchor = get_anchor(element)
      label = hyphen_escape(element.label)
      title = title.join("")
      tag("h#{element.level}"){
        tag(:a, name: anchor, id: anchor){ title }
      } + %Q`<!-- RDLabel: "#{label}" -->`
    end

    def apply_to_TextBlock(element, content)
      content = content.join.chomp
      if ptag_omittable_about_first_textblock_of_listitem?(element)
	content
      else
        tag(:p){ content }
      end
    end

    private

    def ptag_omittable_about_first_textblock_of_listitem?(element)
      return false unless listitem?(element.parent)
      children = element.parent.children
      return true if children.empty?
      return false unless children.first.kind_of?(TextBlock)
      children.drop(1).all?{|e| e.kind_of? List }
    end

    def listitem?(element)
      case element
      when ItemListItem, EnumListItem, DescListItem, MethodListItem
        true
      else
        false
      end
    end

    public

    def apply_to_Verbatim(element)
      tag(:pre){
        element.enum_for(:each_line).map{|line|
          apply_to_String line
        }.join.chomp
      }
    end

    def apply_to_ItemList(element, items)
      tag_block(:ul){ items }
    end

    def apply_to_EnumList(element, items)
      tag_block(:ol){ items }
    end

    def apply_to_DescList(element, items)
      tag_block(:dl){ items }
    end

    def apply_to_MethodList(element, items)
      tag_block(:dl){ items }
    end

    def apply_to_ItemListItem(element, content)
      tag(:li){ content.join("\n").chomp }
    end

    def apply_to_EnumListItem(element, content)
      tag(:li){ content.join("\n").chomp }
    end

    def apply_to_DescListItem(element, term, description)
      anchor = get_anchor(element.term)
      label = hyphen_escape(element.label)
      term = term.join("")
      if description.empty?
	%Q[<dt><a name="#{anchor}" id="#{anchor}">#{term}</a></dt>] +
	%Q[<!-- RDLabel: "#{label}" -->]
      else
        %Q[<dt><a name="#{anchor}" id="#{anchor}">#{term}</a></dt>] +
        %Q[<!-- RDLabel: "#{label}" -->\n] +
        %Q[<dd>\n#{description.join("\n").chomp}\n</dd>]
      end
    end

    def apply_to_MethodListItem(element, term, description)
      term = parse_method(term)  # maybe: term -> element.term
      anchor = get_anchor(element.term)
      label = hyphen_escape(element.label)
      if description.empty?
	%Q[<dt><a name="#{anchor}" id="#{anchor}"><code>#{term}] +
        %Q[</code></a></dt><!-- RDLabel: "#{label}" -->]
      else
        %Q[<dt><a name="#{anchor}" id="#{anchor}"><code>#{term}] +
	%Q[</code></a></dt><!-- RDLabel: "#{label}" -->\n] +
	%Q[<dd>\n#{description.join("\n")}</dd>]
      end
    end

    def apply_to_StringElement(element)
      apply_to_String element.content
    end

    def apply_to_Emphasis(element, content)
      tag(:em){ content.join }
    end

    def apply_to_Code(element, content)
      tag(:code){ content.join }
    end

    def apply_to_Var(element, content)
      tag(:var){ content.join }
    end

    def apply_to_Keyboard(element, content)
      tag(:kbd){ content.join }
    end

    def apply_to_Index(element, content)
      tmp = []
      element.each do |i|
	tmp.push(i) if i.is_a?(String)
      end
      key = meta_char_escape(tmp.join(""))
      if @index.has_key?(key)
	# warning?
	%Q[<!-- Index, but conflict -->#{content.join("")}<!-- Index end -->]
      else
	num = @index[key] = @index.size
	anchor = a_name("index", num)
	%Q[<a name="#{anchor}" id="#{anchor}">#{content.join("")}</a>]
      end
    end

    def apply_to_Reference_with_RDLabel(element, content)
      if element.label.filename
	apply_to_RefToOtherFile(element, content)
      else
	apply_to_RefToElement(element, content)
      end
    end

    def apply_to_Reference_with_URL(element, content)
      %Q[<a href="#{meta_char_escape(element.label.url)}">] +
	%Q[#{content.join("")}</a>]
    end

    def apply_to_RefToElement(element, content)
      content = content.join("")
      if anchor = refer(element)
	content = content.sub(/^function#/, "")
	%Q[<a href="\##{anchor}">#{content}</a>]
      else
	# warning?
	label = hyphen_escape(element.to_label)
	%Q[<!-- Reference, RDLabel "#{label}" doesn't exist -->] +
	  %Q[<em class="label-not-found">#{content}</em><!-- Reference end -->]
	#'
      end
    end

    def apply_to_RefToOtherFile(element, content)
      content = content.join("")
      filename = element.label.filename.sub(/\.(rd|rb)(\.\w+)?$/, "." +
					    OUTPUT_SUFFIX)
      anchor = refer_external(element)
      if anchor
	%Q[<a href="#{filename}\##{anchor}">#{content}</a>]
      else
	%Q[<a href="#{filename}">#{content}</a>]
      end
    end

    def apply_to_Footnote(element, content)
      num = get_footnote_num(element)
      raise ArgumentError, "[BUG?] #{element} is not registered." unless num
      add_foottext(num, content)
      anchor = a_name("footmark", num)
      href = a_name("foottext", num)
      %Q|<a name="#{anchor}" id="#{anchor}" | +
	%Q|href="##{href}"><sup><small>| +
      %Q|*#{num}</small></sup></a>|
    end

    def get_footnote_num(fn)
      raise ArgumentError, "#{fn} must be Footnote." unless fn.is_a? Footnote
      i = @footnotes.index(fn)
      if i
	i + 1
      else
	nil
      end
    end

    def prepare_footnotes(tree)
      @footnotes = tree.find_all{|i| i.is_a? Footnote }
      @foottexts = []
    end
    private :prepare_footnotes

    def apply_to_Foottext(element, content)
      num = get_footnote_num(element)
      raise ArgumentError, "[BUG] #{element} isn't registered." unless num
      anchor = a_name("foottext", num)
      href = a_name("footmark", num)
      content = content.join("")
      %|<a name="#{anchor}" id="#{anchor}" href="##{href}">|+
	%|<sup><small>*#{num}</small></sup></a>| +
	%|<small>#{content}</small><br />|
    end

    def add_foottext(num, foottext)
      raise ArgumentError, "[BUG] footnote ##{num} isn't here." unless
	footnotes[num - 1]
      @foottexts[num - 1] = foottext
    end

    def apply_to_Verb(element)
      apply_to_String element.content
    end

    def apply_to_String(element)
      meta_char_escape element
    end

    def hyphen_escape(str)
      str.gsub /--/, "&shy;&shy;"
    end

    private

    def parse_method(method)
      klass, kind, method, args = MethodParse.analize_method(method)
      if kind == :function
	klass = kind = nil
      else
	kind = MethodParse.kind2str(kind)
      end
      args.gsub!(/&?\w+;?/){ |m|
	if /&\w+;/ =~ m then m else '<var>'+m+'</var>' end }
      case method
      when "self"
	klass, kind, method, args = MethodParse.analize_method(args)
	"#{klass}#{kind}<var>self</var> #{method}#{args}"
      when "[]"
	args.strip!
	args.sub!(/^\((.*)\)$/, '\\1')
	"#{klass}#{kind}[#{args}]"
      when "[]="
	args.tr!(' ', '')
	args.sub!(/^\((.*)\)$/, '\\1')
	ary = args.split(/,/)

	case ary.length
	when 1
	  val = '<var>val</var>'
	when 2
	  args, val = *ary
	when 3
	  args, val = ary[0, 2].join(', '), ary[2]
	end

	"#{klass}#{kind}[#{args}] = #{val}"
      else
	"#{klass}#{kind}#{method}#{args}"
      end
    end

    def meta_char_escape(str)
      str.gsub /[<>&]/, METACHAR
    end

    def make_foottext
      return nil if foottexts.empty?
      content = []
      foottexts.each_with_index do |ft, num|
	content.push(apply_to_Foottext(footnotes[num], ft))
      end
      %|<hr />\n<p class="foottext">\n#{content.join("\n")}\n</p>|
    end

    def a_name(prefix, num)
      "#{prefix}-#{num}"
    end
  end
end

$Visitor_Class = RD::RD2HTMLVisitor
$RD2_Sub_OptionParser = "rd/rd2html-opt"
