require "./shredded_image"

task :default => [:unshred_tokyo, :unshred_lenna, :unshred_mona, :unshred_richard, :unshred_big_sean]

task :unshred_tokyo do
  shredded_image = ShreddedImage.from_file("inputs/TokyoPanoramaShredded.png")
  unshredded_image = shredded_image.unshred
  unshredded_image.save("outputs/TokyoPanorama.png")
end

task :unshred_lenna do
  shredded_image = ShreddedImage.from_file("inputs/lenna_shredded.png")
  unshredded_image = shredded_image.unshred
  unshredded_image.save("outputs/lenna.png")
end

task :unshred_mona do
  shredded_image = ShreddedImage.from_file("inputs/mona_lisa_shredded.png")
  unshredded_image = shredded_image.unshred
  unshredded_image.save("outputs/mona_lisa.png")
end

# Note the slight flaw in the output file.
task :unshred_richard do
  shredded_image = ShreddedImage.from_file("inputs/windowlicker_shredded.png", :brightness_correction => false)
  unshredded_image = shredded_image.unshred
  unshredded_image.save("outputs/windowlicker.png")
end

task :unshred_big_sean do
  shredded_image = ShreddedImage.from_file("inputs/big_sean_shredded.png")
  unshredded_image = shredded_image.unshred
  unshredded_image.save("outputs/big_sean.png")
end
