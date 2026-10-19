def build_report(
    trades,
    start_date,
    end_date,
    include_fees=False,
):
    report = []
    for t in trades:
        report.append(t)
    return report