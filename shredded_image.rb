require "logger"
require "chunky_png"

class ShreddedImage
  LOGGER = Logger.new($stderr)

  def self.from_file(file_path, *args)
    new(ChunkyPNG::Image.from_file(file_path), *args)
  end
  
  def initialize(image, opts = {})
    @brightness_correction = opts.has_key?(:brightness_correction) ? opts[:brightness_correction] : true
    @image = image
  end
  
  def unshred
    strip_width = detect_strip_widths
    ordered_strips = unshuffle_strips(strip_width)
    reassemble_image(ordered_strips)
  end
  
  def width; @image.width; end
  def height; @image.height; end
  def column(*args); @image.column(*args); end
  
  # Threshold at which we consider two pixels to be different. Defaults to
  # a quarter of the range of available values for an 8 bit pixel.
  def px_difference_threshold
    @px_difference_threshold ||= 256 / 4
  end
  
  # How much of a vertical slice of the image must have different pixels before
  # the slice is considered to be different. Defaults to a third of the image height.
  def slice_difference_threshold
    @slice_difference_threshold ||= @image.height / 3
  end

  def r(px); brightness_correct((px & 0xff000000) >> 24); end
  def g(px); brightness_correct((px & 0x00ff0000) >> 16); end
  def b(px); brightness_correct((px & 0x0000ff00) >> 8 ); end
  
  def brightness_correct(px)
    return px unless @brightness_correction
    (((px / 255.0) ** 0.5) * 255.0).to_i
  end
  
  # Given two 24 bit color pixels, determines if they're different by checking each
  # channel individually using the given px difference threshold.
  def pixels_different?(px_a, px_b, threshold = px_difference_threshold)
    (r(px_a) - r(px_b)).abs >= threshold ||
      (g(px_a) - g(px_b)).abs >= threshold ||
      (b(px_a) - b(px_b)).abs >= threshold
  end
  
  def reassemble_image(ordered_strip)
    dest_img = @image.dup
    current_column = 0
    ordered_strip.leftmost.l_to_r do |strip|
      strip.each_column do |col|
        dest_img.replace_column!(current_column, col)
        current_column += 1
      end
    end
    dest_img
  end
  
  # A doubly linked list entry in disguise.
  class Strip
    attr_reader :strip_range
    attr_accessor :left_neighbour, :right_neighbour
    protected :left_neighbour=, :right_neighbour=
    
    def initialize(image, left_bounds, right_bounds)
      @image = image
      @strip_range = left_bounds..right_bounds
    end
    
    def set_left_neighbour(other_strip)
      return if leftmost == other_strip.leftmost
      prev_leftmost = leftmost
      leftmost.left_neighbour = other_strip.rightmost
      other_strip.rightmost.right_neighbour = prev_leftmost
    end
    
    def set_right_neighbour(other_strip)
      return if rightmost == other_strip.rightmost
      prev_rightmost = rightmost
      rightmost.right_neighbour = other_strip.leftmost
      other_strip.leftmost.left_neighbour = prev_rightmost
    end
    
    def set_neighbour(side, other_strip)
      send(:"set_#{side}_neighbour", other_strip)
    end
    
    def leftmost
      return self if @left_neighbour.nil?
      @left_neighbour.leftmost
    end
    
    def rightmost
      return self if @right_neighbour.nil?
      @right_neighbour.rightmost
    end
    
    def l_to_r(&block)
      yield(self)
      @right_neighbour.l_to_r(&block) if @right_neighbour
    end
    
    def each_column
      @strip_range.each { |col| yield(@image.column(col)) }
    end
        
    def left_col
      return @image.column(@strip_range.begin) if leftmost == self
      leftmost.left_col
    end
    
    def right_col
      return @image.column(@strip_range.end) if rightmost == self
      rightmost.right_col
    end
    
    # Assesses the fit of a given strip against the left and right sides of this strip. The side with
    # the lowest number of differences is given as the best fit.
    def assess_fit(other_strip, thresh = @image.px_difference_threshold)
      fit_mapping = [nil, :right, :left]
      left_differences = right_differences = 0
      
      other_strip.right_col.zip(left_col, right_col, other_strip.left_col) do |o_r,s_l,s_r,o_l|
        left_differences  += 1 if @image.pixels_different?(o_r, s_l, thresh)
        right_differences += 1 if @image.pixels_different?(s_r, o_l, thresh)
      end
      
      delta = (left_differences - right_differences).abs      
      best_fit = fit_mapping[left_differences <=> right_differences]
      {:left => left_differences, :right => right_differences, :best => best_fit, :delta => delta}
    end
    
    def inspect
      ranges = []
      leftmost.l_to_r {|strip| ranges << strip.strip_range}
      "<Strip #{ranges.inspect}>"
    end
    alias_method :to_s, :inspect
    
    def side_difference_threshold
      @side_difference_threshold ||= (10 / @image.slice_difference_threshold.to_f) * 100
    end
    
  end
  
  def strip_ranges(strip_width)
    1.upto(width / strip_width).collect do |strip_no|
      next_strip_start = strip_no * strip_width  
      Strip.new(self, next_strip_start - strip_width, next_strip_start - 1)
    end
  end
  
  # Picks a strip, then iterates over the rest to assess which one is the best fit. Merges
  # the two strips by putting them next to each other once it finds a winning strip.
  def unshuffle_strips(strip_width, threshold = slice_difference_threshold)
    strips = strip_ranges(strip_width)
    
    while strips.size > 1 do
      working_strip = strips.pop      
      
      log("Working strip is #{working_strip}")
      
      record = strips.inject(:to_beat => threshold, :strip => nil, :side => nil) do |rec,other_strip|
        differences = working_strip.assess_fit(other_strip)
        best_side = differences[:best]
        next(rec) if best_side.nil? || differences[best_side] >= rec[:to_beat]
        
        log("Absurdly low delta of #{differences[:delta]} for left/right") if differences[:delta] < 5
        
        rec[:to_beat] = differences[best_side]
        rec[:side]    = best_side
        rec[:strip]   = other_strip
        rec
      end

      raise "Couldn't find a matching strip for #{working_strip}" unless record[:strip]
      
      neighbour = strips.delete(record[:strip])
      log("Assigning #{record[:strip]} to the #{record[:side]} side")
      working_strip.set_neighbour(record[:side], neighbour)

      strips.unshift(working_strip)
    end

    strips.last
  end
  
  def detect_strip_widths(threshold = slice_difference_threshold)
    boundaries = get_potential_boundaries(threshold)
    log("Found potential boundaries at: #{boundaries.inspect}")
    strip_width = get_boundary_mode(boundaries)
    log("Assuming a strip width of #{strip_width}px")
    strip_width
  end
  
  def get_boundary_mode(boundaries)
    hist, discard = boundaries.inject([{}, -1]) do |(m_hist,last_bound),curr_bound|
      m_hist[curr_bound - last_bound] &&= m_hist[curr_bound - last_bound] + 1
      m_hist[curr_bound - last_bound] ||= 1
      [m_hist, curr_bound]
    end

    mode_px, mode_count = hist.max_by {|(k,v)| v}
    mode_px
  end
  
  # Finds boundary points in the image by checking pairs of columns and recording any 
  # differences over a threshold.
  def get_potential_boundaries(threshold)
    bounds = (0...(@image.width - 1)).inject([]) do |boundaries,column_index|
      col_a, col_b = @image.column(column_index), @image.column(column_index + 1)
      differences = col_a.zip(col_b).inject(0) do |diff,(px_a,px_b)|
        pixels_different?(px_a, px_b) ? diff + 1 : diff
      end
      
      differences >= threshold ? (boundaries << column_index) : boundaries
    end
    bounds << (@image.width - 1)
  end
  
  def log(msg)
    LOGGER.info(msg)
  end
  
end