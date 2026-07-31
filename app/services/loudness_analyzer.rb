# Measures a file's integrated loudness (EBU R128, LUFS) with ffmpeg's ebur128
# filter. We measure rather than trust tags: the local library's ReplayGain tags
# disagree with the actual audio, and YouTube downloads carry no tags at all.
#
#   LoudnessAnalyzer.new.measure("/path/to.mp3")
#   # => { lufs: -14.9, lufs_hp: -16.4 }, or nil on failure
#
# Two passes: the file as-is, and the file with the bass rolled off. R128's
# K-weighting hardly discounts sub-bass, so a bass-heavy track can spend several
# dB of its budget below 200 Hz — where the ear is least sensitive and party
# speakers roll off anyway — and still meter the same as a midrange-dense track
# that sounds much louder. The gap between the two readings is that bass share;
# Track#loudness_gain_db decides how much of it to correct for.
class LoudnessAnalyzer
  class Error < StandardError; end

  HIGHPASS_HZ = 200

  # The whole file is analysed, not a sample: the gated mean of a track that is
  # quiet for its first half (long builds, DJ mixes, classical) would otherwise
  # read wrong, and that number now drives a gain. ffmpeg decodes at ~200x
  # realtime, so even a 10-minute track costs a couple of seconds per pass.
  def measure(path)
    return nil if path.blank? || !File.exist?(path)

    lufs = integrated(path, "ebur128")
    return nil if lufs.nil?

    { lufs: lufs, lufs_hp: integrated(path, "highpass=f=#{highpass_hz},ebur128") }
  rescue => e
    Rails.logger.warn("[LoudnessAnalyzer] #{path}: #{e.class}: #{e.message}")
    nil
  end

  private

  def highpass_hz = PartyConfig.fetch(:loudness_highpass_hz, HIGHPASS_HZ).to_i

  def integrated(path, filter)
    # No "-v error" here: it suppresses the ebur128 summary we're parsing.
    out, status = Open3.capture2e(
      "ffmpeg", "-nostdin", "-i", path, "-af", filter, "-f", "null", "-"
    )
    raise Error, "ffmpeg exited #{status.exitstatus}" unless status.success?

    parse_integrated(out)
  end

  # The summary block looks like:
  #   Integrated loudness:
  #     I:         -14.9 LUFS
  def parse_integrated(output)
    section = output[/Integrated loudness:(.*?)(?:\n\s*\n|\z)/m]
    value = section&.[](/^\s*I:\s*(-?\d+(?:\.\d+)?)\s*LUFS/, 1)
    value&.to_f
  end
end
