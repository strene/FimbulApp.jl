"""
    Console

Capture of process output (stdout/stderr) into a read-only, REPL-like console
buffer. A minimal terminal emulator interprets the control sequences used by
Jutul's progress bar (carriage return, cursor up, clear line) so the captured
text looks like it would in a terminal.
"""
module Console

using Logging

export ConsoleBuffer, feed!, console_lines, console_version, capture_output

const MAX_LINES = 5000

"""Thread-safe screen buffer that interprets a subset of ANSI/VT100 control sequences."""
mutable struct ConsoleBuffer
    lines::Vector{Vector{Char}}
    row::Int
    col::Int
    pending_bytes::Vector{UInt8}  # Incomplete UTF-8 sequence from previous chunk
    pending_escape::String        # Incomplete escape sequence from previous chunk
    version::Int                  # Incremented on every change
    lock::ReentrantLock
    ConsoleBuffer() = new([Char[]], 1, 1, UInt8[], "", 0, ReentrantLock())
end

"""Number of bytes at the end of `data` that form an incomplete UTF-8 sequence."""
function _incomplete_utf8_tail(data::Vector{UInt8})
    n = length(data)
    for k in 1:min(3, n)
        b = data[n - k + 1]
        if b & 0xC0 == 0x80
            continue  # Continuation byte, keep looking for the lead byte
        end
        len = b < 0x80 ? 1 : b & 0xE0 == 0xC0 ? 2 : b & 0xF0 == 0xE0 ? 3 : b & 0xF8 == 0xF0 ? 4 : 1
        return len > k ? k : 0
    end
    return 0
end

feed!(cb::ConsoleBuffer, s::AbstractString) = feed!(cb, Vector{UInt8}(codeunits(s)))

"""Append raw output bytes to the console, interpreting control sequences."""
function feed!(cb::ConsoleBuffer, data::AbstractVector{UInt8})
    lock(cb.lock) do
        bytes = vcat(cb.pending_bytes, data)
        ntail = _incomplete_utf8_tail(bytes)
        cb.pending_bytes = bytes[end-ntail+1:end]
        text = cb.pending_escape * String(bytes[1:end-ntail])
        cb.pending_escape = ""
        _process!(cb, text)
        _trim!(cb)
        cb.version += 1
    end
    return cb
end

"""Append a line of text written by the app itself (not captured output)."""
function Base.println(cb::ConsoleBuffer, s::AbstractString)
    feed!(cb, s * "\n")
end

function _current_line(cb::ConsoleBuffer)
    while length(cb.lines) < cb.row
        push!(cb.lines, Char[])
    end
    return cb.lines[cb.row]
end

function _put!(cb::ConsoleBuffer, c::Char)
    line = _current_line(cb)
    while length(line) < cb.col - 1
        push!(line, ' ')
    end
    if cb.col <= length(line)
        line[cb.col] = c
    else
        push!(line, c)
    end
    cb.col += 1
end

function _process!(cb::ConsoleBuffer, text::String)
    chars = collect(text)
    i = 1
    n = length(chars)
    while i <= n
        c = chars[i]
        if c == '\e'
            # Escape sequence: ESC [ params final
            if i == n
                cb.pending_escape = "\e"
                return
            end
            if chars[i+1] != '['
                i += 2  # Unsupported two-character escape, skip
                continue
            end
            j = i + 2
            while j <= n && !('@' <= chars[j] <= '~')
                j += 1
            end
            if j > n
                cb.pending_escape = String(chars[i:end])
                return
            end
            _apply_csi!(cb, String(chars[i+2:j-1]), chars[j])
            i = j + 1
            continue
        elseif c == '\n'
            cb.row += 1
            cb.col = 1
            _current_line(cb)
        elseif c == '\r'
            cb.col = 1
        elseif c == '\b'
            cb.col = max(1, cb.col - 1)
        elseif c == '\t'
            for _ in 1:(8 - (cb.col - 1) % 8)
                _put!(cb, ' ')
            end
        elseif isvalid(c) && !iscntrl(c)
            _put!(cb, c)
        end
        i += 1
    end
end

function _apply_csi!(cb::ConsoleBuffer, params::String, final::Char)
    num = something(tryparse(Int, isempty(params) ? "1" : split(params, ';')[1]), 1)
    if final == 'A'      # Cursor up
        cb.row = max(1, cb.row - max(num, 1))
    elseif final == 'B'  # Cursor down
        cb.row += max(num, 1)
        _current_line(cb)
    elseif final == 'C'  # Cursor forward
        cb.col += max(num, 1)
    elseif final == 'D'  # Cursor back
        cb.col = max(1, cb.col - max(num, 1))
    elseif final == 'G'  # Cursor to column
        cb.col = max(num, 1)
    elseif final == 'K'  # Erase in line
        line = _current_line(cb)
        mode = isempty(params) ? 0 : something(tryparse(Int, params), 0)
        if mode == 0
            resize!(line, min(length(line), cb.col - 1))
        elseif mode == 1
            for k in 1:min(cb.col, length(line))
                line[k] = ' '
            end
        else
            empty!(line)
        end
    end
    # Colors (m), cursor visibility (h/l) etc. are ignored
end

function _trim!(cb::ConsoleBuffer)
    excess = length(cb.lines) - MAX_LINES
    if excess > 0
        deleteat!(cb.lines, 1:excess)
        cb.row = max(1, cb.row - excess)
    end
end

"""Current console content as a vector of strings."""
function console_lines(cb::ConsoleBuffer)
    lock(cb.lock) do
        lines = String.(cb.lines)
        # Drop a trailing empty line (cursor sitting at the start of a new line)
        if !isempty(lines) && isempty(lines[end])
            pop!(lines)
        end
        return lines
    end
end

console_version(cb::ConsoleBuffer) = lock(() -> cb.version, cb.lock)

const _capture_lock = ReentrantLock()

"""
    capture_output(f, cb::ConsoleBuffer; echo=true)

Run `f()` with stdout and stderr redirected into `cb`. When `echo` is true the
output is also forwarded to the original stdout, so it still shows up in the
terminal running the server. Only one capture can be active at a time.

Log messages from `f` (and tasks it spawns) go to the console, while log
messages from other tasks, such as the web server's request log, keep going to
the terminal.
"""
function capture_output(f, cb::ConsoleBuffer; echo::Bool=true)
    lock(_capture_lock) do
        oldout, olderr = stdout, stderr
        pipe = Pipe()
        Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
        read_loop = () -> begin
            while !eof(pipe)
                data = readavailable(pipe)
                echo && write(oldout, data)
                feed!(cb, data)
            end
        end
        # Read on the interactive pool when available, so output shows up while
        # `f` is busy computing on a default thread
        reader = Threads.nthreads(:interactive) > 0 ? Threads.@spawn(:interactive, read_loop()) : @async(read_loop())
        old_logger = global_logger(ConsoleLogger(olderr))
        redirect_stdout(pipe.in)
        redirect_stderr(pipe.in)
        try
            return with_logger(f, ConsoleLogger(pipe.in))
        finally
            redirect_stdout(oldout)
            redirect_stderr(olderr)
            global_logger(old_logger)
            close(pipe.in)
            wait(reader)
        end
    end
end

end # module
