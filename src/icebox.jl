using LinearAlgebra
using SparseArrays
using DormandPrince
using DocStringExtensions

include("outerprod.jl")
include("simulator.jl")


using PyCall


py"""
import numpy as np

def vec_pos(j1, j2, m1, m2):
    id1 = (j1 - m1)
    id2 = (j2 - m2)
    return int(id1 * (2 * j2 + 1) + id2)

def J_pos(Jmax, Ji, Mi):
    '''
    Ji in range(Jmin, Jmin+1, ..., Jmax)
    '''
    return int((Ji - Mi) + ((2 * Jmax + 1) + (2 * (Ji+1) + 1)) * (Jmax - Ji) / 2)

def uni_array(start, end, step):
    return np.arange(start, end + step, step)

def CG_Coef(j1, j2):
    '''
    计算(j1, [-j1,-j1+1, ... ,j1] ) tensor (j2, [-j2, -j2+1, ... , j2] ) 空间的 J invariant 子空间直和形式
    即( j1-j2, spin-z ), ( j1 - j2 + 1, spin-z, ), ... , ( j1 + j2, spin-z )子空间的形式
    assume j1 >= j2
    维度: 
    (2j1+1)*(2j2+1) = [ 2(j1 - j2) +1 ] + [ 2(j1-j2+1) + 1] + ... + [ 2(j1 + j2) +1 ]

    认为 (j1, s1) tensor (j2, s2) 占据的行是 s1 * (2j2+1) + s2 (input Vector)
    '''

    mat = np.zeros([(int)(2 * j1 + 1) * (int)(2 * j2 + 1),
                   (int)(2 * j1 + 1) * (int)(2 * j2 + 1)])

    row = 0

    for J in uni_array(j1 + j2, np.abs(j1 - j2), -1):
        # 单独计算每个J的最大的M所对应的变换系数
        if (J == (j1 + j2)):
            mat[0][vec_pos(j1, j2, j1, j2)] = 1
        else:
            is_first_m1 = False
            for m1 in uni_array(j1, -j1, -1):
                m2 = J - m1
                if (m2 > j2 or m2 < - j2):
                    continue
                if (is_first_m1 == False):  # 确定第一个m1
                    sum = 0
                    for uper_J in uni_array(m1 + m2 + 1, j1 + j2, 1):
                        sum += mat[J_pos(j1 + j2, uper_J, m1 + m2)
                                   ][vec_pos(j1, j2, m1, m2)] ** 2
                    # (J, J)对应的(m1, m2)应该与其他向量组正交
                    mat[J_pos(j1 + j2, J, J)][vec_pos(j1, j2, m1, m2)
                                              ] = np.sqrt(1 - sum)
                    is_first_m1 = True
                else:
                    sum = 0
                    for uper_J in uni_array(m1 + m2 + 1, j1 + j2, 1):
                        sum += mat[J_pos(j1 + j2, uper_J, m1 + m2)][vec_pos(j1, j2, m1, m2)] * \
                            mat[J_pos(j1 + j2, uper_J, m1+m2)
                                ][vec_pos(j1, j2, m1+1, m2-1)]

                    mat[J_pos(j1 + j2, J, J)][vec_pos(j1, j2, m1, m2)] = (0 - sum) / \
                        mat[J_pos(j1 + j2, J, J)][vec_pos(j1, j2, m1+1, m2-1)]

        for M in uni_array(J, - J + 1, -1):  # 作用降算子
            for m1 in uni_array(j1, -j1, -1):
                m2 = M - m1 - 1
                if (m2 > j2 or m2 < - j2):
                    continue
                mat[J_pos(j1 + j2, J, M - 1)][vec_pos(j1, j2, m1, m2)] += mat[J_pos(j1 + j2,
                                                                                    J, M)][vec_pos(j1, j2, m1+1, m2)] * np.sqrt((j1 + 1 + m1) * (j1 - m1))
                mat[J_pos(j1 + j2, J, M - 1)][vec_pos(j1, j2, m1, m2)] += mat[J_pos(j1 + j2,
                                                                                    J, M)][vec_pos(j1, j2, m1, m2+1)] * np.sqrt((j2 + 1 + m2) * (j2 - m2))
                mat[J_pos(j1 + j2, J, M - 1)][vec_pos(j1, j2, m1, m2)
                                              ] /= np.sqrt((J + 1 - M) * (J + M))

    return mat

if __name__ == "__main__":
    mat = CG_Coef(1, 1/2)
    print(mat.round(decimals=2))

"""

function CG_Coef(j1, j2)
    mat = py"CG_Coef"(j1, j2)
    return mat
end


function sparse_identity(n::Int)
    return spdiagm(0 => ones(ComplexF64, 2^n))
end

# write an algorithm to count the number of bits of a number
function count_bits(n::Int)
    count = 0
    if n == 0
        return 1
    end 
    while n > 0
        count += 1
        n = n >> 1
    end
    return count
end

# write an algorithm to generate the CG matrix with the given twoJ, nSTAT, nP, usedSTAT, nowP
function CG_matrix(twoJ, nSTAT::Int, nP::Int, usedSTAT::Int, nowP::Int)

    real_input_vec_position = []
    for i in 0:twoJ
        push!(real_input_vec_position, i * (2^(nSTAT - usedSTAT)) * (2^(nowP)))
        push!(real_input_vec_position, i * (2^(nSTAT - usedSTAT)) * (2^(nowP)) + 1)
    end
    Jplusqubits = count_bits(twoJ+1)
    real_output_vec_position_Jplus = []
    for i in 0:(twoJ+1)
        push!(real_output_vec_position_Jplus, i * (2^(nSTAT - Jplusqubits)) * (2^(nowP)))
    end
    Jminusqubits = count_bits(twoJ-1)
    real_output_vec_position_Jminus = []
    for i in 0:(twoJ-1)
        push!(real_output_vec_position_Jminus, i * (2^(nSTAT - Jminusqubits)) * (2^(nowP)) + 1)
    end

    real_output_vec_position = [real_output_vec_position_Jplus...,real_output_vec_position_Jminus...]

    # println(real_output_vec_position)
    # println(real_input_vec_position)
    mat = CG_Coef(twoJ/2, 1/2)
    # println(mat' * mat)


    ret_mat = sparse_identity(nSTAT + nowP)
    
    for i in 1:length(real_output_vec_position)
        ret_mat[real_output_vec_position[i] + 1, real_output_vec_position[i] + 1] = 0
        ret_mat[real_input_vec_position[i] + 1, real_input_vec_position[i] + 1] = 0
    end

    for i in 1:length(real_output_vec_position)
        for j in 1:length(real_input_vec_position)
            ret_mat[real_output_vec_position[i] + 1, real_input_vec_position[j] + 1] = mat[i, j]
        end
    end

    common = intersect(real_output_vec_position, real_input_vec_position)
    filter_output = setdiff(real_output_vec_position, common)
    filter_input = setdiff(real_input_vec_position, common)
    for i in 1:length(filter_output)
        ret_mat[filter_input[i] + 1, filter_output[i] + 1] = 1
    end

    return ret_mat
end

function control_CG_transform(twoJ, nSP::Int, nSTAT::Int, nP::Int, usedSTAT::Int, nowP::Int)
    U = kron(CG_matrix(twoJ, nSTAT, nP, usedSTAT, nowP), sparse_identity(nP-nowP))
    I = sparse_identity(nSTAT + nP)

    control_0_mat = sparse([1],[1],[1], 2, 2)
    control_1_mat = sparse([2],[2],[1], 2, 2)
    pre_identity_SP = sparse_identity(twoJ - 1)
    suf_identity_SP = sparse_identity(nSP - twoJ)
    
    control_0_mat = kron(kron(pre_identity_SP, control_0_mat), suf_identity_SP)
    control_1_mat = kron(kron(pre_identity_SP, control_1_mat), suf_identity_SP)

    ret_mat = kron(control_0_mat, I) + kron(control_1_mat, U)
    return ret_mat
end


