require 'sanitize'
require 'redcarpet'

module UserTextHelper

  def format_user_text(text, markup_type)
    return '' if text.nil?
    return text if markup_type == 'text'
    return format_user_text_html(text) if markup_type == 'html'
    return format_user_text_markdown(text) if markup_type == 'markdown'
    return ''
  end

  # Returns the plain text representation of the passed markup
  def format_user_text_as_plain(text, markup_type)
    Sanitize.clean(format_user_text(text, markup_type))
  end

  private

  def format_user_text_html(text)
    Sanitize.clean(text, get_html_sanitize_config).html_safe
  end

  def format_user_text_markdown(text)
    Sanitize.clean(@@markdown.render(text), get_markdown_sanitize_config).html_safe
  end

  def get_html_sanitize_config
    if @@html_sanitize_config.nil?
      @@html_sanitize_config = get_markdown_sanitize_config.dup
      fix_whitespace = lambda do |env|
        node = env[:node]
        return unless node.text?
        return if has_ancestor(node, 'pre')
        node.content = node.content.lstrip if element_is_block(node.previous_sibling)
        node.content = node.content.rstrip if element_is_block(node.next_sibling)
        return if node.text.empty?
        return unless node.text.include?("\n")
        replace_text_with_node(node, "\n", Nokogiri::XML::Node.new('br', node.document))
      end

      @@html_sanitize_config[:transformers] << fix_whitespace
    end
    return @@html_sanitize_config
  end

  def get_markdown_sanitize_config
    if @@markdown_sanitize_config.nil?
      @@markdown_sanitize_config = Sanitize::Config::BASIC.dup
      @@markdown_sanitize_config[:elements] = @@markdown_sanitize_config[:elements].dup
      @@markdown_sanitize_config[:elements].concat(['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'img', 'hr', 'del', 'ins', 'table', 'tr', 'th', 'td', 'thead', 'tbody', 'tfoot', 'span', 'div', 'tt', 'center', 'ruby', 'rt', 'rp', 'video', 'details', 'summary'])
      @@markdown_sanitize_config[:attributes] = @@markdown_sanitize_config[:attributes].merge('img' => ['src', 'alt', 'height', 'width'], 'video' => ['src', 'poster', 'height', 'width'], 'details' => ['open'], :all => ['title', 'name'])
      @@markdown_sanitize_config[:protocols] = @@markdown_sanitize_config[:protocols].merge('img' => {'src'  => ['https']}, 'video' => {'src'  => ['https']})
      @@markdown_sanitize_config[:remove_contents] = ['script', 'style']
      @@markdown_sanitize_config[:add_attributes] = @@markdown_sanitize_config[:add_attributes].merge('video' => {'controls' => 'controls'})

      yes_follow = lambda do |env|
        follow_domains = ['mozillazine.org', 'mozilla.org', 'mozilla.com', 'userscripts.org', 'userstyles.org', 'mozdev.org', 'photobucket.com', 'facebook.com', 'chrome.google.com', 'github.com', 'greasyfork.org', 'openuserjs.org']
        return unless env[:node_name] == 'a'
        node = env[:node]
        href = nil
        href = node['href'].downcase unless node['href'].nil?
        follow = false
        if href.nil?
          # missing the href, we don't want a rel here
          follow = true
        elsif href =~ Sanitize::REGEX_PROTOCOL
          # external link, let's figure out the domain if it's http or https
          match = /https?:\/\/([^\/]+).*/.match(href)
          # check domain against our list, including subdomains
          if !match.nil?
            follow_domains.each do |d|
              if match[1] == d or match[1].ends_with?('.' + d)
                follow = true
                break
              end
            end
          end
        else
          # internal link
          follow = true
        end
        if follow
          # take out any rel value the user may have provided
          node.delete('rel')
        else
          node['rel'] = 'nofollow'
        end

        # make a config that allows the rel attribute and does not include this transformer
        # do a deep copy of anything we're going to change
        config_allows_rel = env[:config].dup
        config_allows_rel[:attributes] = config_allows_rel[:attributes].dup
        config_allows_rel[:attributes]['a'] = config_allows_rel[:attributes]['a'].dup
        config_allows_rel[:attributes]['a'] << 'rel'
        config_allows_rel[:add_attributes] = config_allows_rel[:add_attributes].dup
        config_allows_rel[:add_attributes]['a'] = config_allows_rel[:add_attributes]['a'].dup
        config_allows_rel[:add_attributes]['a'].delete('rel')
        config_allows_rel[:transformers] = config_allows_rel[:transformers].dup
        config_allows_rel[:transformers].delete(yes_follow)

        Sanitize.clean_node!(node, config_allows_rel)

        # whitelist so the initial clean call doesn't strip the rel
        return {:node_whitelist => [node]}
      end
      linkify_urls = lambda do |env|
        node = env[:node]
        return unless node.text?
        return if has_ancestor(node, 'a')
        return if has_ancestor(node, 'pre')
        url_reference = node.text.match(/(\s|^|\()(https?:\/\/[^\s\)\]]*)/i)
        return if url_reference.nil?
        replace_text_with_link(node, url_reference[2], url_reference[2], url_reference[2])
      end

      @@markdown_sanitize_config[:transformers] = [linkify_urls, yes_follow]
    end
    return @@markdown_sanitize_config
  end

  @@markdown_sanitize_config = nil
  @@html_sanitize_config = nil

  def replace_text_with_link(node, original_text, link_text, url)
    # the text itself becomes a link
    link = Nokogiri::XML::Node.new('a', node.document)
    link['href'] = url
    link.add_child(Nokogiri::XML::Text.new(link_text, node.document))
    replace_text_with_node(node, original_text, link)
  end

  def replace_text_with_node(node, text, node_to_insert)
    node_text = node.text
    replaced_original_node = false

    # Can't use split because we'd swallow consecutive delimiters.

    # Put everything in a fragment first and insert it all at once for performance.
    fragment = Nokogiri::HTML::DocumentFragment.new(node.document)
    while node_text
      index = node_text.index(text)
      if index.nil?
        fragment << Nokogiri::XML::Text.new(node_text, node.document)
        break
      end
      if replaced_original_node
        fragment << Nokogiri::XML::Text.new(node_text[0, index], node.document)
      else
        node.content = node_text[0, index]
        replaced_original_node = true
      end
      fragment << node_to_insert.dup
      node_text = node_text[(index+text.length)..]
    end

    node.add_next_sibling(fragment)
  end

  def has_ancestor(node, ancestor_node_name)
    until node.nil?
      return true if node.name == ancestor_node_name
      node = node.parent
    end
    return false
  end

  def element_is_block(node)
    return false if node.nil?
    # https://github.com/rgrove/sanitize/issues/108
    d = Nokogiri::HTML::ElementDescription[node.name]
    return !d.nil? && d.block?
  end

  @@markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new({:link_attributes => {:rel => 'nofollow'}}), :fenced_code_blocks => true, :lax_spacing => true)

end
