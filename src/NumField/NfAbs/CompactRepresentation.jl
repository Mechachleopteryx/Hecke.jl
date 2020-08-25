@doc Markdown.doc"""
    compact_presentation(a::FacElem{nf_elem, AnticNumberField}, n::Int = 2; decom, arb_prec = 100, short_prec = 1000) -> FacElem
Computes a presentation $a = \prod a_i^{n_i}$ where all the exponents $n_i$ are powers of $n$
and, the elements $a$ are "small", generically, they have a norm bounded by $d^{n/2}$ where
$d$ is the discriminant of the maximal order.
As the algorithm needs the factorisation of the principal ideal generated by $a$, it can
be passed in in \code{decom}.
"""
function compact_presentation(a::FacElem{nf_elem, AnticNumberField}, nn::Int = 2; decom=false, arb_prec = 100, short_prec = 128)

  n = fmpz(nn)

  K = base_ring(a)
  if isempty(a.fac)
    return a
  end
 
  if typeof(decom) == Bool
    ZK = lll(maximal_order(K))
    de::Dict{NfOrdIdl, fmpz} = factor_coprime(a, IdealSet(ZK), refine = true)
  else
    #de = Dict{NfOrdIdl, fmpz}((p, v) for (p, v) = decom)
    de = Dict((p, v) for (p, v) = decom)
    if length(decom) == 0
      ZK = lll(maximal_order(K))
    else
      ZK = order(first(keys(decom)))
    end
  end
  de_inv = Dict{NfOrdIdl, NfOrdFracIdl}()

  be = FacElem(K(1))

  if !(decom isa Bool)
    @hassert :CompactPresentation 1 (length(de) == 0 && isone(abs(factored_norm(a)))) ||
                                    (abs(factored_norm(a)) == factored_norm(FacElem(de)))
  end

  v = conjugates_arb_log_normalise(a, arb_prec)
  if length(de) == 0
    _v = FlintZZ(1)
  else
    _v = maximum(abs, values(de))+1
  end

  #Step 1: reduce the ideal in a p-power way...

  A = ideal(ZK, 1)
  @vprint :CompactPresentation 1 "First reduction step\n"
  cached_red = Dict{NfOrdIdl, Dict{Int, Tuple{NfOrdIdl, FacElem{nf_elem, AnticNumberField}}}}()
  n_iterations = Int(flog(_v, n))
  for _k = n_iterations:-1:0
    @vprint :CompactPresentation 3 "Reducing the support: step $(_k) / $(n_iterations)\n"
    B = Dict{NfOrdIdl, Int}()
    for (p, vv) in de
      e_p = Int(div(vv, n^_k) % nn)
      if iszero(e_p)
        continue
      end
      if haskey(cached_red, p)
        Dp = cached_red[p]
        if haskey(Dp, e_p)
          Ap, ap = Dp[e_p]       
        else
          Ap, ap = power_reduce(p, fmpz(e_p))
          Dp[e_p] = (Ap, ap)
        end
        add_to_key!(B, Ap, 1)
        mul!(be, be, ap^(-(n^_k)))
        v -= Ref(n^_k) .* conjugates_arb_log_normalise(ap, arb_prec)
      else
        Dp = Dict{Int, Tuple{NfOrdIdl, FacElem{nf_elem, AnticNumberField}}}()
        Ap, ap = power_reduce(p, fmpz(e_p))
        Dp[e_p] = (Ap, ap)
        cached_red[p] = Dp
        add_to_key!(B, Ap, 1)
        v -= Ref(n^_k) .* conjugates_arb_log_normalise(ap, arb_prec)
        mul!(be, be, ap^(-(n^_k)))
      end
    end
    add_to_key!(B, A, n)
    @vtime :CompactPresentation 3 A, alpha = reduce_ideal(FacElem(B))
    mul!(be, be, alpha^(-(n^_k)))
    #be *= alpha^(-(n^_k))
    v -= Ref(n^_k) .* conjugates_arb_log_normalise(alpha, arb_prec)
  end
  if length(be.fac) > 1
    delete!(be.fac, K(1))
  end

  #Step 2: now reduce the infinite valuation

  r1, r2 = signature(K)
 
  if length(de) == 0
    m = FlintZZ(1)
  else
    m = maximum(abs, values(de))
  end
  m = max(m, 1)
  mm = abs_upper_bound(log(1+maximum(abs, v))//log(n), fmpz)
  k = max(ceil(Int, log(m)/log(n)), Int(mm))

  de = Dict(A => fmpz(1))
  delete!(de, ideal(ZK, 1))
  
  @hassert :CompactPresentation 1 length(de) == 0 && isone(abs(factored_norm(a*be))) == 1 ||
                                  abs(factored_norm(a*be)) == factored_norm(FacElem(de))

  @hassert :CompactPresentation 2 length(de) != 0 || isone(ideal(ZK, a*be)) 
  @hassert :CompactPresentation 2 length(de) == 0 || ideal(ZK, a*be) == FacElem(de)

  while k>=1
    @vprint :CompactPresentation 1 "k now: $k\n"
    D = Dict((p, div(fmpz(v), n^k)) for (p, v) = de if v >= n^k)
    if length(D) == 0
      A = FacElem(Dict(ideal(ZK, 1) => 1))
    else
      A = FacElem(D)
    end
    vv = arb[x//n^k for x = v]
    vvv = fmpz[]
    el_embs = a*be
    for i=1:r1
      while !radiuslttwopower(vv[i], -5)
        arb_prec *= 2
        v = conjugates_arb_log_normalise(el_embs, arb_prec)
        vv = arb[x//n^k for x = v]
      end
      push!(vvv, round(fmpz, vv[i]//log(2)))
    end
    for i=r1+1:r1+r2
      while !radiuslttwopower(vv[i], -5)
        arb_prec *= 2
        v = conjugates_arb_log_normalise(el_embs, arb_prec)
        vv = arb[x//n^k for x = v]
      end
      local r = round(fmpz, vv[i]//log(2)//2)
      push!(vvv, r)
      push!(vvv, r)
    end
    @assert abs(sum(vvv)) <= degree(K)
    @vtime :CompactPresentation 1 eA = (simplify(evaluate(A, coprime = true)))
    @vtime :CompactPresentation 1 id = inv(eA)
    @vtime :CompactPresentation 1 b = short_elem(id, matrix(FlintZZ, 1, length(vvv), vvv), prec = short_prec) # the precision needs to be done properly...
   
    @assert abs(norm(b)//norm(id)) <= abs(discriminant(ZK)) # the trivial case

    for (p, v) in A
      if isone(p)
        continue
      end
      de[p] -= n^k*v
    end

    @vtime :CompactPresentation 1 B = simplify(b*eA)
    @assert isone(B.den)
    B1 = B.num   
    @assert norm(B1) <= abs(discriminant(ZK))

    @vprint :CompactPresentation 1 "Factoring ($(B1.gen_one), $(B1.gen_two)) of norm $(norm(B1))\n"
    @vtime :CompactPresentation 1 lfB1 = factor_easy(B1)
    for (p, _v) = lfB1
      if haskey(de, p)
        de[p] += _v*n^k
      elseif isprime_known(p) && isprime(p)
        insert_prime_into_coprime!(de, p, _v*n^k)
      else
        de = insert_into_coprime(de, p, _v*n^k)
      end
    end
    v_b = conjugates_arb_log_normalise(b, arb_prec)
    @v_do :CompactPresentation 2 @show old_n = sum(x^2 for x = v)
    v += Ref(n^k) .* v_b
    @v_do :CompactPresentation 2 @show new_n = sum(x^2 for x = v)
    @v_do :CompactPresentation 2 @show old_n / new_n 
    
    add_to_key!(be.fac, b, n^k)
    #be *= FacElem(b)^(n^k)
    @hassert :CompactPresentation 1 length(de) == 0 && isone(abs(factored_norm(a*be))) == 1 ||
                                    abs(factored_norm(a*be)) == factored_norm(FacElem(de))
    @hassert :CompactPresentation 2 length(de) != 0 || isone(ideal(ZK, a*be)) 
    @hassert :CompactPresentation 2 length(de) == 0 || ideal(ZK, a*be) == FacElem(de)
    k -= 1
  end
  if isempty(de)
    de[ideal(ZK, 1)] = 1
  end
  @hassert :CompactPresentation 2 length(de) != 0 || isone(ideal(ZK, a*be)) 
  @hassert :CompactPresentation 2 length(de) == 0 || ideal(ZK, a*be) == FacElem(de)
  @hassert :CompactPresentation 1 length(de) == 0 && isone(abs(factored_norm(a*be))) == 1 ||
                                    factored_norm(ideal(ZK, a*be)) == abs(factored_norm(FacElem(de)))
  @vprint :CompactPresentation 1 "Final eval...\n"
  @vtime :CompactPresentation 1 A = evaluate(FacElem(de), coprime = true)
  @vtime :CompactPresentation 1 b_ev = evaluate_mod(a*be, A)
  inv!(be)
  add_to_key!(be.fac, b_ev, fmpz(1))
  return be
end

function insert_prime_into_coprime!(de::Dict{NfOrdIdl, fmpz}, p::NfOrdIdl, e::fmpz)
  @assert !isone(p)
  P = p.gen_one
  for (k, v) in de
    if k.gen_one % P == 0
      if k.splitting_type[2] == 0
        #k is not known to be prime, so p could divide...
        v1 = valuation(k, p)
        if v1 == 0
          continue
        end
        #since it divides k it cannot divide any other (coprime!)
        p2 = simplify(k*inv(p)^v1).num
        if !isone(p2)
          de[p2] = v
        end
        de[p] = v*v1+e
        delete!(de, k)
        return nothing
      else
        #both are know to be prime, and p is new to the dict.
        @assert p != k
      end
    end
  end
  de[p] = e
  return nothing
end

function insert_into_coprime(de::Dict{NfOrdIdl, fmpz}, p::NfOrdIdl, e::fmpz)
  @assert !isone(p)
  P = p.gen_one
  cp = NfOrdIdl[]
  for (k, v) in de
    if !iscoprime(k.gen_one, P)
      push!(cp, k)
    end
  end
  if isempty(cp)
    de[p] = e
    return de
  end
  push!(cp, p)
  cp = coprime_base(cp)
  de1 = Dict{NfOrdIdl, fmpz}()
  for (k, v) in de
    if iscoprime(k.gen_one, P)
      de1[k] = v
    end
  end
  for pp in cp
    vp = e*valuation(p, pp)
    for (k, v) in de
      vp += valuation(k, pp)*v
    end
    if !iszero(vp)
      de1[pp] = vp
    end
  end
  return de1
end



#TODO: use the log as a stopping condition as well
@doc Markdown.doc"""
    evaluate_mod(a::FacElem{nf_elem, AnticNumberField}, B::NfOrdFracIdl) -> nf_elem
Evaluates $a$ using CRT and small primes. Assumes that the ideal generated by $a$ is in fact $B$.
Useful in cases where $a$ has huge exponents, but the evaluated element is actually "small".
"""
function evaluate_mod(a::FacElem{nf_elem, AnticNumberField}, B::NfOrdFracIdl)
  K = base_ring(a)
  if isempty(a.fac)
    return one(K)
  end
  p = fmpz(next_prime(p_start))
  
  ZK = order(B)
  dB = denominator(B)*denominator(basis_matrix(ZK, copy = false))
  
  @hassert :CompactPresentation 1 factored_norm(B) == abs(factored_norm(a))
  @hassert :CompactPresentation 2 B == ideal(order(B), a)

  @assert order(B) === ZK
  pp = fmpz(1)
  re = K(0)
  threshold = 3
  if degree(K) > 30
    threshold = div(degree(K), 10)
  end
  while (true)
    dt = prime_decomposition_type(ZK, Int(p))
    fl = true
    for i = 1:length(dt)
      if dt[i][1] > threshold
        fl = false
        break
      end
    end
    if !fl
      p = next_prime(p)
      continue
    end
    me = modular_init(K, p)
    mp = Ref(dB) .* modular_proj(a, me)
    m = modular_lift(mp, me)
    if isone(pp)
      re = m
      pp = p
    else
      p2 = pp*p
      last = re
      re = induce_inner_crt(re, m, pp*invmod(pp, p), p2, div(p2, 2))
      if re == last
        return re//dB
      end
      pp = p2
    end
    @hassert :CompactPresentation 1 nbits(pp) < 10000
    p = next_prime(p)
  end
end


function Hecke.ispower(a::FacElem{nf_elem, AnticNumberField}, n::Int; with_roots_unity = false, decom = false, trager = false)
  if n == 1
    return true, a
  end
  @assert n > 1
  K = base_ring(a)
  if isempty(a.fac)
    return true, FacElem(one(K))
  end
  anew_fac = Dict{nf_elem, fmpz}()
  rt = Dict{nf_elem, fmpz}()
  for (k, v) in a
    q, r = divrem(v, n)
    if !iszero(q)
      rt[k] = q
    end
    if !iszero(r)
      anew_fac[k] = r
    end
  end
  if isempty(anew_fac)
    K = base_ring(a)
    if isempty(rt)
      rt[one(K)] = 1
    end
    return true, FacElem(rt)
  end
  #anew = FacElem(anew_fac)
  #c = conjugates_arb_log(a, 64)
  #c1 = conjugates_arb_log(anew, 64)
  #b = maximum(fmpz[upper_bound(abs(x), fmpz) for x in c])
  #b1 = maximum(fmpz[upper_bound(abs(x), fmpz) for x in c1])
  #if b <= 2*b1
    return _ispower(a, n, with_roots_unity = with_roots_unity, decom = decom, trager = trager)
  #end
  #=
  @vprint :Saturate :3 "Using the new element with the exponent bound\n"
  if b <= 10*b1
    fl, res = _ispower(anew, n, with_roots_unity = with_roots_unity);
  else
    fl, res1 = ispower(evaluate(anew), n, with_roots_unity = with_roots_unity, trager = trager)
    res = FacElem(res1)
  end
  if !fl
    return fl, res
  end
  if !isempty(rt)
    res = FacElem(rt)*res
  end
  return true, res
  =#
end

function _ispower(a::FacElem{nf_elem, AnticNumberField}, n::Int; with_roots_unity = false, decom = false, trager = false)

  K = base_ring(a)
  ZK = maximal_order(K)
  @vprint :Saturate 1 "Computing compact presentation\n"
  @vtime :Saturate 1 c = Hecke.compact_presentation(a, n, decom = decom)
  b = one(K)
  d = Dict{nf_elem, fmpz}()
  for (k, v) = c.fac
    q, r = divrem(v, n)
    if r < 0
      r += n
      q -= 1
      @assert r > 0
      @assert n*q+r == v
    end
    d[k] = q
    mul!(b, b, k^r)
  end
  
  if isempty(d)
    d[one(K)] = fmpz(1)
  end
  df = FacElem(d) 
  @show "hallo"
  @hassert :CompactPresentation 2 evaluate(df^n*b *inv(a))== 1
  
  den = denominator(b, ZK)
  fl, den1 = ispower(den, n)
  if fl
    den = den1
  end
  @time x, _ = IsPower.ispower_mod_p(b*den^n, n)
#  fl, x = ispower((den^n)*b, n, with_roots_unity = with_roots_unity, isintegral = true, trager = trager)
  if fl
    @hassert :CompactPresentation 2 x^n == b*(den^n)
    add_to_key!(df.fac, K(den), -1)
    return fl, df*x
  else
    return fl, df
  end
end

