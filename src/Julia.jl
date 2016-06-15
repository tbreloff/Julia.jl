
module Julia


using Glob
using DataFrames

const _dir = joinpath(relpath(Base.source_dir()), "..")

# -----------------------------------------------------------------


function scrape_md(filename)

    # get the category, don't process some files
    category = split(split(filename, "/")[end], ".")[1]
    category in ("LICENSE", "README") && return []
    
    subcategory = ""
    records = NTuple{5,UTF8String}[]

    subcategory = ""
    records = NTuple{5,UTF8String}[]
    
    # process the  lines
    f = open(filename)
    for l in eachline(f)

        l = strip(l)
        if length(l) == 0
            continue

        # handle subcategories
        elseif l[1] == '#'
            subcategory = join(split(l)[2:end])

        # collect repo info
        elseif l[1] == '+'
            tmp = split(l, " :: ")
            repotuple = split(tmp[1], "](")
            length(repotuple) == 2 || continue
            reponame = repotuple[1][4:end]
            repourl = repotuple[2][1:end-1]
            length(repourl) > 4 || continue
            repourl[1:4] == "http" || continue
            desc = length(tmp) > 1 ? join(tmp[2:end]...) : ""
            push!(records, (category, subcategory, reponame, repourl, desc))
        end
    end
    close(f)
    println("Processed $(length(records)) records in category $category.")
    records

    records             
end


function create_repo_database()
    # loop over all markdown files in the root directory, appending the records to the list
    records = []
    for filename in glob(joinpath(_dir, "*.md"))
        append!(records, scrape_md(filename))
    end

    # save a csv file
    println("Writing out $(length(records)) records.")
    f = open(joinpath(_dir, "db.csv"), "w")
    for record in records
        write(f, "\"")
        write(f, join(record, "\",\""))
        write(f, "\"\n")
    end
    close(f)
end


# -----------------------------------------------------------------

# uses GitHub.jl to pull some info

using GitHub
const _auth = authenticate(ENV["OAUTH_TOKEN"])

function repo_db_as_dataframe()
    readtable(joinpath(_dir, "db.csv"), header=false, names=[:group,:subgroup,:name,:url,:desc])
end


function get_url_from_df(df, i)
    url = df[i,:url]
    url = join(split(url,"/")[end-1:end], "/")
end

function get_contributions(url)
    c = contributors(url, auth=_auth)[1]
    tups = [(get(d["contributor"].login), d["contributions"]) for d in c]
    [t[1] for t in tups], [t[2] for t in tups]
end

function build_contributors_dataframe(df)
    contribs = DataFrame()
    for i = 1:size(df,1)
        url = get_url_from_df(df,i)
        try
            url[end-2:end] == ".jl" || continue
            info("trying $url")
            us,cs = get_contributions(url)
            n = length(us)
            contribs = vcat(contribs, DataFrame(
                url = url,
                users=(us,),
                contribs=(cs,),
                group = df[i,:group],
                subgroup = df[i,:subgroup]
            ))
            info("success... n=$n")
        catch err
            @show err
        end
    end
    contribs
end


function get_stargazers(url)
    s = stargazers(url, auth=_auth)[1]
    [get(o.login) for o in s]
end

function build_stargazers_dataframe(df)
    sg = DataFrame()
    for i = 1:size(df,1)
        url = get_url_from_df(df,i)
        try
            url[end-2:end] == ".jl" || continue
            info("trying $url")
            gazers = get_stargazers(url)
            n = length(gazers)
            repo = df[i,:name][1:end-3]
            sg = vcat(sg, DataFrame(
                repo = repo,
                url = url,
                gazers = (gazers,),
                group = df[i,:group],
                subgroup = df[i,:subgroup]
            ))
            info("success... n=$n")
        catch err
            @show err
        end
    end
    sg
end

function create_github_tables()
    df = repo_db_as_dataframe()
    c_df = build_contributors_dataframe(df)
    writetable(joinpath(_dir, "contributors.csv"), c_df)
    sg_df = build_stargazers_dataframe(df)
    writetable(joinpath(_dir, "stargazers.csv"), sg_df)
    c_df, sg_df
end



# -----------------------------------------------------------------

end # module
