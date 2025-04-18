{ epkgs, version }:

epkgs.elpaBuild {
    pname = "testrun";
    ename = "testrun";
    version = version;
    src = [ ./testrun.el ];
    packageRequires = [];
    meta = {};
}
