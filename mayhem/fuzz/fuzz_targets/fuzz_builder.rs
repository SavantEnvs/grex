#![no_main]

// Port of the fork's original fuzz_builder harness to the current grex public
// API: RegExpConfig is no longer public, so the same option coverage is driven
// through RegExpBuilder's with_*/without_* methods instead of a config struct.

use libfuzzer_sys::{
    arbitrary::{Arbitrary, Result, Unstructured},
    fuzz_target,
};

use grex::RegExpBuilder;

const STRING_COUNT: usize = 4;
const STRING_LENGTH: usize = 15;

#[derive(Debug)]
struct InputData {
    strings: Vec<String>,
}

#[derive(Arbitrary, Debug)]
struct TestInput {
    is_digit_converted: bool,
    is_non_digit_converted: bool,
    is_space_converted: bool,
    is_non_space_converted: bool,
    is_word_converted: bool,
    is_non_word_converted: bool,
    is_capturing_group_enabled: bool,
    is_non_ascii_char_escaped: bool,
    is_astral_code_point_converted_to_surrogate: bool,
    is_start_anchor_disabled: bool,
    is_end_anchor_disabled: bool,
    is_output_colorized: bool,

    data: InputData,
}

impl<'a> Arbitrary<'a> for InputData {
    fn arbitrary(u: &mut Unstructured<'a>) -> Result<Self> {
        let num_strings = u.int_in_range(1..=(STRING_COUNT as u8))?;
        let mut strings = Vec::new();

        while strings.len() < num_strings as usize && !u.is_empty() {
            let bytes_remaining = u.len();
            let max_length = STRING_LENGTH.min(bytes_remaining) as u8;

            let string_size = u.int_in_range(0..=max_length)?;
            let bytes = u.bytes(string_size as usize)?;
            strings.push(String::from_utf8_lossy(bytes).to_string());
        }

        if strings.is_empty() {
            strings.push(String::new());
        }

        Ok(InputData { strings })
    }

    fn size_hint(_depth: usize) -> (usize, Option<usize>) {
        let min = 0;
        // 1: number of strings; 1: size of each string
        let max = 1 + (1 + STRING_LENGTH) * STRING_COUNT;
        (min, Some(max))
    }
}

fuzz_target!(|input: TestInput| {
    let mut builder = RegExpBuilder::from(&input.data.strings);

    if input.is_digit_converted {
        builder.with_conversion_of_digits();
    }
    if input.is_non_digit_converted {
        builder.with_conversion_of_non_digits();
    }
    if input.is_space_converted {
        builder.with_conversion_of_whitespace();
    }
    if input.is_non_space_converted {
        builder.with_conversion_of_non_whitespace();
    }
    if input.is_word_converted {
        builder.with_conversion_of_words();
    }
    if input.is_non_word_converted {
        builder.with_conversion_of_non_words();
    }
    if input.is_capturing_group_enabled {
        builder.with_capturing_groups();
    }
    if input.is_non_ascii_char_escaped {
        builder.with_escaping_of_non_ascii_chars(input.is_astral_code_point_converted_to_surrogate);
    }
    if input.is_start_anchor_disabled && input.is_end_anchor_disabled {
        builder.without_anchors();
    } else if input.is_start_anchor_disabled {
        builder.without_start_anchor();
    } else if input.is_end_anchor_disabled {
        builder.without_end_anchor();
    }
    // with_syntax_highlighting is gated behind a non-default feature in current
    // grex; the colorized-output flag is kept in the input layout but unused.
    let _ = input.is_output_colorized;

    let _ = builder.build();
});
