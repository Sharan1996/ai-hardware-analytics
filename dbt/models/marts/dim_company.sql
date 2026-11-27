select
    cik,
    ticker,
    company_name,
    chain_role,
    case chain_role
        when 'memory'              then 'Memory chips (DRAM, HBM, NAND)'
        when 'custom_silicon'      then 'Custom AI chips and networking'
        when 'custom_silicon_peer' then 'Peer: custom silicon'
        when 'compute_peer'        then 'Peer: CPUs and GPUs'
    end                                   as chain_role_label,
    chain_role in ('memory', 'custom_silicon') as is_focus_company
from {{ ref('companies') }}