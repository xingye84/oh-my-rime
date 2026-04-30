-- 五笔拼音混输候选优化：
-- 1. 按「准确五笔 -> 准确拼音 -> 推测五笔 -> 推测拼音 -> 其他」重排候选
-- 2. 给中文候选追加五笔编码提示，便于观察混输结果

local M = {}
local shared = require("wubi_mixed_shared")

local function is_chinese(text)
    return text and utf8.len(text) and utf8.len(text) >= 1
        and not text:match("^[%a%d%p%s]+$")
end

local function normalize_comment(comment)
    if not comment or comment == "" then
        return ""
    end
    return comment:gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function normalize_code(code)
    if not code or code == "" then
        return nil
    end
    return code:gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function is_pinyin_comment(comment)
    local normalized = normalize_comment(comment)
    return normalized ~= "" and normalized:match("^[%a%s']+$") and not normalized:match("%d")
end

local function extract_pinyin_code(cand, input_code)
    local comment_code = normalize_comment(cand.comment)
    if is_pinyin_comment(comment_code) then
        return comment_code .. " "
    end

    local normalized_input = normalize_code(input_code)
    if normalized_input and normalized_input ~= "" then
        return normalized_input .. " "
    end

    return nil
end

local function is_pinyin_candidate(cand)
    local cand_type = tostring(cand.type or "")
    if cand_type == "reverse_lookup" then
        return true
    end
    return is_pinyin_comment(cand.comment)
end

local function is_predicted_candidate(cand, input_len)
    local cand_type = tostring(cand.type or "")
    if cand_type == "completion" or cand_type == "sentence" then
        return true
    end

    local cand_end = cand._end
    if type(cand_end) == "number" and cand_end < input_len then
        return true
    end

    return false
end

local function classify_candidate(cand, input_len)
    if not is_chinese(cand.text or "") then
        return 5
    end

    local is_pinyin = is_pinyin_candidate(cand)
    local is_predicted = is_predicted_candidate(cand, input_len)

    if not is_pinyin and not is_predicted then
        return 1
    end
    if is_pinyin and not is_predicted then
        return 2
    end
    if not is_pinyin and is_predicted then
        return 3
    end
    return 4
end

local function lookup_wubi_code(cand, reverse_db)
    if not reverse_db then
        return nil
    end
    local text = cand.text or ""
    if not is_chinese(text) then
        return nil
    end

    local code = reverse_db:lookup(text)
    if not code or code == "" then
        return nil
    end

    code = code:match("^%S+")
    if not code or code == "" then
        return nil
    end

    return code
end

local function build_comment(cand, input_code, wubi_code)
    local cand_type = tostring(cand.type or "")
    local current_comment = normalize_comment(cand.comment)

    if cand_type == "reverse_lookup" then
        local pinyin = normalize_code(input_code) or current_comment
        if wubi_code then
            return pinyin .. " [" .. wubi_code .. "]"
        end
        return pinyin
    end

    if wubi_code then
        local tag = "[" .. wubi_code .. "]"
        if current_comment == "" then
            return tag
        end
        if current_comment:find(tag, 1, true) or current_comment == wubi_code then
            return current_comment
        end
        return current_comment .. " " .. tag
    end

    return current_comment
end

local function rewrite_comment(cand, input_code, reverse_db)
    local wubi_code = lookup_wubi_code(cand, reverse_db)
    local next_comment = build_comment(cand, input_code, wubi_code)

    local genuine = cand:get_genuine()
    local orig = genuine.comment or ""
    if next_comment == orig then
        return
    end
    genuine.comment = next_comment
end

function M.init(env)
    local config = env.engine.schema.config
    env.name_space = env.name_space:gsub("^%*", "")
    env.dictionary = config:get_string("translator/dictionary") or ""
end

function M.func(input, env)
    local context = env.engine.context
    local code = context.input or ""

    if code == "" or not code:match("^[A-Za-z'`]+$") then
        shared.candidates = nil
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    shared.candidates = {}

    if not env.reverse_db and env.dictionary ~= "" then
        local ok, db = pcall(ReverseDb, "build/" .. env.dictionary .. ".reverse.bin")
        env.reverse_db = ok and db or false
    end

    local buckets = {{}, {}, {}, {}, {}}
    for cand in input:iter() do
        if is_chinese(cand.text or "") and is_pinyin_candidate(cand) then
            local pinyin_code = extract_pinyin_code(cand, code)
            if pinyin_code then
                shared.candidates[cand.text] = pinyin_code
            end
        end
        local bucket = classify_candidate(cand, #code)
        table.insert(buckets[bucket], cand)
    end

    for _, bucket in ipairs(buckets) do
        for _, cand in ipairs(bucket) do
            rewrite_comment(cand, code, env.reverse_db or nil)
            yield(cand)
        end
    end
end

return M
