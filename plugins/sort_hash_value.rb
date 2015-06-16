# Title: Sort Hash by Value
# Author: Michael Kashin http://networkop.github.io
# Description: Sorts hash by its values. Used to output top category list
#
# Example 1:
# {% for category in site.categories | sort_hash_by_value %}
#
module Jekyll
  module SortHashByValue
    def sort_hash_by_value(my_hash)
	  my_hash.sort_by {|k,v| v.size}.reverse
	end
  end
end

Liquid::Template.register_filter(Jekyll::SortHashByValue)
