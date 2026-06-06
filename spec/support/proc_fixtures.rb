# frozen_string_literal: true

# Real lambdas defined in a stable source file so #filter_label(expand: true)
# specs have a Proc whose #source_location points at a readable, parseable file.
# Each helper returns a fresh lambda whose source snippet is known and asserted.
module ProcFixtures
  module_function

  # A single-line lambda. Its slice should be "-> { compute_reading_time }".
  def single_line_lambda
    -> { compute_reading_time }
  end

  # A multi-line block-style proc. Its slice collapses to one line.
  def multi_line_proc
    proc do
      first_step
      second_step
    end
  end
end
